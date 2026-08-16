#!/usr/bin/env python3
"""Check domain registration via authoritative RDAP registry services.

Input:  one bare registrable domain per line in ./domains.txt
Output: CSV results in ./domain_results.csv

RDAP status meanings used here:
  HTTP 200 -> TAKEN (a registration object exists)
  HTTP 404 -> AVAILABLE (no registration object exists)
  anything else -> UNKNOWN (do not guess)
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import re
import socket
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json"
USER_AGENT = "domain-availability-checker/1.0 (RDAP; personal-use)"
RETRYABLE_HTTP = {408, 425, 429, 500, 502, 503, 504}
DOMAIN_RE = re.compile(
    r"^(?=.{1,253}\.?$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.?$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Result:
    domain: str
    status: str
    detail: str


def get_json(url: str, timeout: float) -> dict[str, Any]:
    request = Request(
        url,
        headers={
            "Accept": "application/rdap+json, application/json",
            "User-Agent": USER_AGENT,
        },
    )
    with urlopen(request, timeout=timeout) as response:
        return json.load(response)


def load_rdap_map(timeout: float) -> dict[str, list[str]]:
    """Map each TLD to the authoritative RDAP base URL(s) from IANA."""
    data = get_json(BOOTSTRAP_URL, timeout)
    mapping: dict[str, list[str]] = {}
    for tlds, urls in data.get("services", []):
        for tld in tlds:
            # Prefer HTTPS when a registry publishes more than one endpoint.
            mapping[tld.lower()] = sorted(
                urls, key=lambda u: not u.startswith("https://")
            )
    if not mapping:
        raise RuntimeError("IANA returned an empty RDAP bootstrap map")
    return mapping


def normalize_domain(line: str) -> str | None:
    value = line.strip()
    if not value or value.startswith("#"):
        return None

    # Accept a bare domain or URL. Anything after whitespace is treated as a comment.
    value = value.split()[0]
    parsed = urlsplit(value if "://" in value else "//" + value)
    host = (parsed.hostname or "").rstrip(".").lower()
    if host.startswith("www."):
        host = host[4:]
    try:
        host = host.encode("idna").decode("ascii")
    except UnicodeError as exc:
        raise ValueError(f"invalid internationalized domain: {exc}") from exc
    if not DOMAIN_RE.fullmatch(host):
        raise ValueError("invalid domain syntax")
    return host


def request_status(url: str, timeout: float, retries: int) -> tuple[int | None, str]:
    headers = {
        "Accept": "application/rdap+json, application/json",
        "User-Agent": USER_AGENT,
    }
    for attempt in range(retries + 1):
        try:
            with urlopen(Request(url, headers=headers), timeout=timeout) as response:
                # Consume a small amount so the connection can be cleanly closed.
                response.read(256)
                return response.status, ""
        except HTTPError as exc:
            if exc.code == 404:
                return 404, ""
            if exc.code not in RETRYABLE_HTTP or attempt == retries:
                return exc.code, f"HTTP {exc.code}"
            retry_after = exc.headers.get("Retry-After", "")
            delay = float(retry_after) if retry_after.isdigit() else 0.75 * (2**attempt)
        except (URLError, TimeoutError, socket.timeout, OSError) as exc:
            if attempt == retries:
                return None, str(exc.reason if isinstance(exc, URLError) else exc)
            delay = 0.75 * (2**attempt)
        time.sleep(delay + random.uniform(0.0, 0.25))
    return None, "retry limit reached"


def check_domain(
    domain: str, rdap_map: dict[str, list[str]], timeout: float, retries: int
) -> Result:
    tld = domain.rsplit(".", 1)[-1]
    base_urls = rdap_map.get(tld)
    if not base_urls:
        return Result(domain, "UNKNOWN", f"no RDAP service published for .{tld}")

    errors: list[str] = []
    for base_url in base_urls:
        url = base_url.rstrip("/") + "/domain/" + quote(domain, safe=".-")
        code, detail = request_status(url, timeout, retries)
        if code == 200:
            return Result(domain, "TAKEN", "registered")
        if code == 404:
            return Result(domain, "AVAILABLE", "not found in registry RDAP")
        errors.append(
            detail or (f"HTTP {code}" if code is not None else "request failed")
        )
    return Result(domain, "UNKNOWN", "; ".join(errors))


def read_domains(path: Path) -> tuple[list[str], list[Result]]:
    domains: list[str] = []
    invalid: list[Result] = []
    seen: set[str] = set()
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        try:
            domain = normalize_domain(line)
        except ValueError as exc:
            invalid.append(Result(line.strip(), "INVALID", f"line {number}: {exc}"))
            continue
        if domain and domain not in seen:
            seen.add(domain)
            domains.append(domain)
    return domains, invalid


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Bulk-check domain registration using RDAP"
    )
    parser.add_argument("-i", "--input", type=Path, default=Path("domains.txt"))
    parser.add_argument("-o", "--output", type=Path, default=Path("domain_results.csv"))
    parser.add_argument("-w", "--workers", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=12.0)
    parser.add_argument("--retries", type=int, default=2)
    args = parser.parse_args()

    if not args.input.is_file():
        parser.error(f"input file not found: {args.input}")
    if not 1 <= args.workers <= 20:
        parser.error("--workers must be between 1 and 20")

    try:
        domains, invalid = read_domains(args.input)
        rdap_map = load_rdap_map(args.timeout)
    except (OSError, HTTPError, URLError, ValueError, RuntimeError) as exc:
        parser.error(str(exc))

    by_domain: dict[str, Result] = {}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(
                check_domain, domain, rdap_map, args.timeout, args.retries
            ): domain
            for domain in domains
        }
        for future in as_completed(futures):
            domain = futures[future]
            try:
                result = future.result()
            except (
                Exception
            ) as exc:  # Keep one unexpected failure from aborting the batch.
                result = Result(domain, "UNKNOWN", f"unexpected error: {exc}")
            by_domain[domain] = result
            print(f"{result.domain:<40} {result.status}")

    # Preserve input order and let csv.writer correctly escape every field.
    results = [by_domain[d] for d in domains] + invalid
    with args.output.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(("domain", "status", "detail"))
        writer.writerows((r.domain, r.status, r.detail) for r in results)

    counts = {
        status: sum(r.status == status for r in results)
        for status in ("AVAILABLE", "TAKEN", "UNKNOWN", "INVALID")
    }
    print(f"\nSaved {len(results)} results to {args.output}")
    print("  " + ", ".join(f"{key}={value}" for key, value in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
