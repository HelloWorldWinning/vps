#!/usr/bin/env python3
"""Collect domain lists and check Cloudflare Registrar availability (Debian/Python 3.9+).

SETUP (once):
  sudo apt-get install python3-venv
  python3 -m venv ~/.venvs/domain-sieve
  ~/.venvs/domain-sieve/bin/pip install requests idna tldextract
  export CLOUDFLARE_ACCOUNT_ID='your_32_character_account_id'
  export CLOUDFLARE_API_TOKEN='your_registrar_api_token'

RUN:
  ~/.venvs/domain-sieve/bin/python domain_sieve.py names.txt more.txt ./lists
  ~/.venvs/domain-sieve/bin/python domain_sieve.py ./lists --recursive
  ~/.venvs/domain-sieve/bin/python domain_sieve.py --resume ./domain_sieve_runs/RUN

Folder discovery: *.txt, case-insensitive; explicit files may have any extension.
One domain per line; blank lines and full-line # comments are ignored. URLs and
subdomains are rejected rather than silently rewritten. IDNs use IDNA/UTS #46.
Public-suffix validation uses tldextract's bundled ICANN snapshot, offline.
Unknown suffixes are sent to the provider; private suffixes are not treated as
independent registrar namespaces (e.g. a.eu.org requires its own service).
Update tldextract periodically for a newer bundled public suffix snapshot.

Output: report.md (first H1: available) plus state.sqlite3 in a new run directory.
No purchase/registration endpoint is called. Availability is time-sensitive.
Resume retries unknown/pending entries, keeping other results for 15 minutes by
default; older valid entries are checked again. --max-age-hours controls this.
--recheck-all refreshes every syntactically valid entry. Resume uses the saved
input snapshot; to add/change input files, start a new run.

Exit codes: 0=resolved (possibly zero available); 1=fatal error; 2=CLI error;
3=unresolved/unsupported entries; 130=interrupted. Invalid lines are counted
separately. --dry-run validates without API calls and exits 0.

Cloudflare setup and current API documentation:
https://developers.cloudflare.com/registrar/registrar-api/
https://developers.cloudflare.com/api/resources/registrar/methods/check/
"""

import argparse
import collections
import datetime as dt
import email.utils
import fcntl
import json
import math
import os
from pathlib import Path
import random
import re
import sqlite3
import sys
import tempfile
import time
import uuid

VERSION = "1.0.0"
SCHEMA = 1
STATUSES = ("available", "premium", "unavailable", "unsupported", "unknown", "invalid")


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def log(message):
    print(message, file=sys.stderr, flush=True)


def atomic_write(path, content):
    fd, temporary = tempfile.mkstemp(prefix=".report-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def md(value):
    # Escape untrusted input, including literal backticks and Markdown links.
    value = str(value)
    value = "".join(c if c.isprintable() else " " for c in value)
    return re.sub(r"([\\`*_{}\[\]()#+.!|<>~\-])", r"\\\1", value)


def dependencies():
    try:
        import idna
        import requests
        import tldextract
    except ImportError:
        raise RuntimeError(
            "Missing dependencies. Create a venv (see this file's SETUP), then run: "
            "~/.venvs/domain-sieve/bin/pip install requests idna tldextract"
        ) from None
    return idna, requests, tldextract


def normalize(raw, idna, extractor):
    candidate = raw.strip()
    if any(c in candidate for c in "/:@*?#") or any(c.isspace() for c in candidate):
        return candidate, "Use a bare domain, without URL, email, wildcard, or whitespace"
    try:
        # IDNA also normalizes Unicode dot variants. Strip exactly one root dot.
        domain = idna.encode(candidate, uts46=True, std3_rules=True).decode("ascii").lower()
        if domain.endswith("."):
            domain = domain[:-1]
        labels = domain.split(".")
        if len(domain) > 253 or len(labels) < 2 or any(
            not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
            for label in labels
        ):
            raise ValueError()
        if labels[-1].isdigit():
            return domain, "IP addresses and numeric suffixes are not domain candidates"
    except (idna.IDNAError, UnicodeError, ValueError):
        return candidate.lower(), "Invalid domain syntax or IDNA encoding"
    suffix = extractor(domain)
    if suffix.suffix and (not suffix.domain or suffix.subdomain):
        return domain, "Not an independent registration candidate under the ICANN suffix snapshot"
    # Unknown suffix: do not guess the registrable boundary; let the API decide.
    return domain, ""


def discover(inputs, recursive, output_root):
    files = []
    seen = set()
    for value in inputs:
        path = Path(value).expanduser().resolve(strict=True)
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = []
            for root, dirs, names in os.walk(path, followlinks=False):
                dirs[:] = sorted(d for d in dirs if not d.startswith(".")
                                  and (Path(root) / d).resolve() != output_root
                                  and not (Path(root) / d / "state.sqlite3").exists())
                for name in sorted(names):
                    item = Path(root) / name
                    if name.lower().endswith(".txt") and not item.is_symlink() and item.is_file():
                        candidates.append(item.resolve())
                if not recursive:
                    break
        else:
            raise RuntimeError(f"Not a regular file or folder: {path}")
        for item in sorted(candidates):
            if item not in seen:
                files.append(item)
                seen.add(item)
    if not files:
        raise RuntimeError("No input files found; folders are scanned for .txt files only")
    return files


def initialize(db, files, idna, extractor):
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE domains (
            name TEXT PRIMARY KEY, status TEXT NOT NULL, reason TEXT NOT NULL,
            checked_at TEXT, result TEXT NOT NULL DEFAULT '{}'
        );
        CREATE TABLE sources (name TEXT, file TEXT, line INTEGER, original TEXT);
    """)
    stats = collections.Counter(files=len(files))
    with db:
        for file in files:
            with file.open(encoding="utf-8-sig", errors="strict") as handle:
                for line_number, line in enumerate(handle, 1):
                    stats["lines"] += 1
                    raw = line.strip()
                    if not raw or raw.startswith("#"):
                        stats["ignored_lines"] += 1
                        continue
                    name, error = normalize(raw, idna, extractor)
                    cursor = db.execute(
                        "INSERT OR IGNORE INTO domains(name,status,reason) VALUES(?,?,?)",
                        (name, "invalid" if error else "unknown", error or "Not checked yet"))
                    if cursor.rowcount == 0:
                        stats["duplicates"] += 1
                    db.execute("INSERT INTO sources VALUES(?,?,?,?)",
                               (name, str(file), line_number, raw))
        if not db.execute("SELECT 1 FROM domains LIMIT 1").fetchone():
            raise RuntimeError("Inputs contain no domain candidates")
        for key, value in {"schema": SCHEMA, "created_at": now(), "stats": dict(stats),
                           "files": [str(p) for p in files], "version": VERSION}.items():
            db.execute("INSERT INTO meta VALUES(?,?)", (key, json.dumps(value)))


def save(db, name, status, reason, checked=None, result=None):
    with db:
        db.execute("UPDATE domains SET status=?,reason=?,checked_at=?,result=? WHERE name=?",
                   (status, reason, checked or now(), json.dumps(result or {}), name))


def render(db, run, note, dry_run=False):
    rows = db.execute("SELECT * FROM domains ORDER BY rowid").fetchall()
    counts = collections.Counter(row["status"] for row in rows)
    output = []
    for status in STATUSES:
        output.extend([f"# {status}", ""])
        selected = [r for r in rows if r["status"] == status]
        if not selected:
            output.extend(["None.", ""])
        for row in selected:
            line = f"- {md(row['name'])}"
            if status == "available":
                pricing = json.loads(row["result"]).get("pricing")
                if isinstance(pricing, dict):
                    details = []
                    for key, label in (("registration_cost", "registration"), ("renewal_cost", "renewal")):
                        if pricing.get(key) is not None:
                            details.append(f"{label}: {md(pricing[key])} {md(pricing.get('currency', ''))}")
                    if details:
                        line += " — " + "; ".join(details)
            else:
                line += " — " + md(row["reason"])
            if row["checked_at"]:
                line += f"; checked: {row['checked_at']}"
            output.append(line)
            if status == "invalid":
                source = db.execute("SELECT file,line FROM sources WHERE name=? LIMIT 1", (row["name"],)).fetchone()
                if source:
                    output.append(f"  - Source: {md(source['file'])}, line {source['line']}")
        if selected:
            output.append("")
    meta = {r["key"]: json.loads(r["value"]) for r in db.execute("SELECT * FROM meta")}
    complete = not dry_run and not counts["unknown"] and not counts["unsupported"]
    output.extend(["# summary", "", f"- Provider: Cloudflare Registrar Check API",
                   f"- Run created: {meta['created_at']}", f"- Report generated: {now()}",
                   f"- Outcome: {md(note)}", f"- Fully resolved: {'yes' if complete else 'no'}",
                   f"- Unique entries (including invalid): {len(rows)}"])
    output.extend(f"- {key}: {counts[key]}" for key in STATUSES)
    output.extend(f"- Input {key}: {value}" for key, value in meta["stats"].items())
    output.extend(["", "Available means positively confirmed registrable through this provider at the recorded time.",
                   "Unavailable can mean registered, reserved, or otherwise blocked. Unsupported is not taken.",
                   "Premium status does not itself confirm registrability. No domains were reserved or purchased.",
                   "Recheck before purchase. Suffix validation uses the installed tldextract ICANN snapshot.",
                   "", "Input files:", ""])
    output.extend(f"- {md(p)}" for p in meta["files"])
    atomic_write(run / "report.md", "\n".join(output) + "\n")
    return counts


class StopRun(RuntimeError):
    pass


class BatchRejected(RuntimeError):
    pass


class Cloudflare:
    def __init__(self, account, token, args, requests):
        self.requests = requests
        self.args = args
        self.url = f"https://api.cloudflare.com/client/v4/accounts/{account}/registrar/domain-check"
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {token}",
                                     "User-Agent": f"domain-sieve/{VERSION}"})
        self.next_request = 0.0
        self.calls = 0

    def retry_delay(self, response, attempt):
        delay = min(30.0, 2.0 ** attempt) + random.random()
        if response is not None:
            value = response.headers.get("Retry-After", "")
            try:
                wait = float(value)
            except ValueError:
                try:
                    stamp = email.utils.parsedate_to_datetime(value)
                    wait = stamp.timestamp() - time.time()
                except (TypeError, ValueError, OverflowError):
                    wait = 0.0
            if math.isfinite(wait):
                delay = max(delay, wait)
        if delay > self.args.max_retry_wait:
            raise StopRun("Server requests a long retry wait; checkpoint saved. Resume later.")
        return delay

    def request(self, names):
        last_error = "Temporary API failure"
        for attempt in range(self.args.retries + 1):
            time.sleep(max(0.0, self.next_request - time.monotonic()))
            response = None
            try:
                self.calls += 1
                response = self.session.post(self.url, json={"domains": names},
                                             timeout=(10, self.args.timeout), allow_redirects=False)
                code = response.status_code
                if code in (401, 403):
                    raise StopRun(f"HTTP {code}: verify account ID, token permissions, and Registrar API access")
                if code == 429 or code == 408 or 500 <= code <= 599:
                    last_error = f"HTTP {code} after retries"
                elif code == 400 or code == 422:
                    # Split bad batches; never invent a per-domain status from a batch error.
                    raise BatchRejected(f"HTTP {code}: API rejected the candidate or batch")
                elif not 200 <= code < 300:
                    raise StopRun(f"Unexpected HTTP {code}; check API access and endpoint")
                else:
                    try:
                        data = response.json()
                    except ValueError:
                        data = None
                    if isinstance(data, dict) and data.get("success") is True:
                        result = data.get("result")
                        if isinstance(result, dict) and isinstance(result.get("domains"), list):
                            return result["domains"]
                    # Error codes only, not full messages/headers which might expose secrets.
                    codes = []
                    if isinstance(data, dict) and isinstance(data.get("errors"), list):
                        codes = [str(e.get("code")) for e in data["errors"] if isinstance(e, dict)]
                    if codes:
                        safe_codes = ",".join(c for c in codes if re.fullmatch(r"\d+", c))
                        raise StopRun(f"API returned success=false (codes: {safe_codes or 'unavailable'})")
                    last_error = "Malformed or unsuccessful API response after retries"
            except self.requests.exceptions.SSLError:
                raise StopRun("TLS verification failed; check the system clock and CA certificates") from None
            except self.requests.exceptions.RequestException:
                last_error = "Network connection or timeout failure after retries"
            finally:
                self.next_request = time.monotonic() + self.args.interval
            if attempt < self.args.retries:
                delay = self.retry_delay(response, attempt)
                log(f"Retry {attempt + 1}/{self.args.retries} in {delay:.1f}s ({len(names)} domains)")
                time.sleep(delay)
        raise RuntimeError(last_error)


def interpret(item):
    flag = item.get("registrable")
    reason = item.get("reason")
    tier = item.get("tier")
    if tier == "premium" or reason == "domain_premium":
        return "premium", "Premium classification; availability may require another registrar"
    if flag is True and reason is None and tier == "standard":
        return "available", "Confirmed registrable, standard tier"
    if flag is False:
        if reason == "domain_unavailable":
            return "unavailable", "Registered, reserved, or otherwise unavailable"
        if reason == "extension_disallows_registration":
            return "unavailable", "Registry currently disallows registration on this extension"
        if reason in ("extension_not_supported", "extension_not_supported_via_api"):
            return "unsupported", reason
    return "unknown", "Unrecognized or inconsistent API status; no availability assumed"


def check_batch(client, db, names):
    try:
        items = client.request(names)
    except BatchRejected as exc:
        if len(names) > 1:
            middle = len(names) // 2
            check_batch(client, db, names[:middle])
            check_batch(client, db, names[middle:])
        else:
            save(db, names[0], "unknown", str(exc))
        return
    except StopRun:
        raise
    except RuntimeError as exc:
        for name in names:
            save(db, name, "unknown", str(exc))
        return
    by_name = collections.defaultdict(list)
    for item in items:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            by_name[item["name"].lower().rstrip(".")].append(item)
    missing = []
    for name in names:
        matches = by_name[name]
        if len(matches) != 1:
            if not matches and len(names) > 1:
                missing.append(name)
            else:
                save(db, name, "unknown", "Missing or duplicate domain result from API")
            continue
        status, reason = interpret(matches[0])
        # Store only documented non-secret fields; do not persist HTTP headers.
        clean = {key: matches[0][key] for key in ("name", "registrable", "reason", "tier", "pricing")
                 if key in matches[0]}
        save(db, name, status, reason, result=clean)
    for name in missing:
        check_batch(client, db, [name])


def parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("inputs", nargs="*", help="Files and/or folders containing domain lists")
    p.add_argument("--recursive", action="store_true", help="Search subfolders for .txt files")
    p.add_argument("--output-dir", type=Path, default=Path("domain_sieve_runs"), help="Parent of new run directory")
    p.add_argument("--resume", type=Path, help="Existing run directory; do not supply inputs")
    p.add_argument("--recheck-all", action="store_true", help="Recheck all valid entries when resuming")
    p.add_argument("--max-age-hours", type=float, default=0.25, help="Resume result freshness (default: 0.25 hours)")
    p.add_argument("--batch-size", type=int, default=20, help="Domains per request: 1..20")
    p.add_argument("--interval", type=float, default=1.0, help="Minimum seconds between completed requests")
    p.add_argument("--timeout", type=float, default=30.0, help="HTTP read timeout in seconds")
    p.add_argument("--retries", type=int, default=4, help="Additional attempts per temporary request failure")
    p.add_argument("--max-retry-wait", type=float, default=300.0, help="Checkpoint and stop if Retry-After exceeds this")
    p.add_argument("--dry-run", action="store_true", help="Validate only; no API requests or credentials needed")
    p.add_argument("--version", action="version", version=VERSION)
    return p


def main(argv=None):
    p = parser()
    args = p.parse_args(argv)
    if bool(args.resume) == bool(args.inputs):
        p.error("Supply input file/folder paths OR --resume RUN_DIRECTORY")
    if not 1 <= args.batch_size <= 20 or not 0 <= args.retries <= 10:
        p.error("--batch-size must be 1..20 and --retries must be 0..10")
    for key in ("interval", "timeout", "max_age_hours", "max_retry_wait"):
        value = getattr(args, key)
        if not math.isfinite(value) or value < 0 or (key == "timeout" and value == 0):
            p.error(f"--{key.replace('_', '-')} must be finite and nonnegative (timeout must be positive)")
    os.umask(0o077)
    db = lock = client = None
    initialized = False
    run = None
    note = "Not started"
    code = 0
    try:
        idna, requests, tldextract = dependencies()
        # Offline snapshot: avoids silent network fetches/failures during validation.
        extractor = tldextract.TLDExtract(suffix_list_urls=(), cache_dir=None,
                                         include_psl_private_domains=False)
        if args.resume:
            run = args.resume.expanduser().resolve(strict=True)
            if not (run / "state.sqlite3").is_file():
                raise RuntimeError("Resume directory does not contain state.sqlite3")
        else:
            parent = args.output_dir.expanduser().resolve()
            files = discover(args.inputs, args.recursive, parent)
            parent.mkdir(parents=True, exist_ok=True)
            run = parent / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8])
            run.mkdir(mode=0o700)
        lock = (run / ".lock").open("a")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another process is using this run directory") from None
        db = sqlite3.connect(str(run / "state.sqlite3"))
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA synchronous=FULL")
        if args.resume:
            row = db.execute("SELECT value FROM meta WHERE key='schema'").fetchone()
            if not row or json.loads(row[0]) != SCHEMA:
                raise RuntimeError("Unsupported checkpoint schema")
        else:
            initialize(db, files, idna, extractor)
        initialized = True
        log(f"Run directory: {run}")
        if args.resume:
            cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=args.max_age_hours)
            with db:
                for row in db.execute("SELECT name,status,checked_at FROM domains").fetchall():
                    if row["status"] == "invalid":
                        continue
                    stale = not row["checked_at"] or dt.datetime.fromisoformat(row["checked_at"]) < cutoff
                    if args.recheck_all or stale or row["status"] == "unknown":
                        db.execute("UPDATE domains SET status='unknown',reason='Pending fresh check',checked_at=NULL,result='{}' WHERE name=?",
                                   (row["name"],))
        pending = [r[0] for r in db.execute("SELECT name FROM domains WHERE status='unknown' ORDER BY rowid")]
        render(db, run, "Validation complete; checks pending", args.dry_run)
        log(f"Unique entries: {db.execute('SELECT count(*) FROM domains').fetchone()[0]}; to check: {len(pending)}")
        if args.dry_run:
            note = "Dry run: input validation only; availability not checked"
        elif pending:
            account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", os.environ.get("ACCOUNT_ID", "")).strip()
            token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
            if not re.fullmatch(r"[0-9a-fA-F]{32}", account) or not token or any(c.isspace() for c in token):
                raise RuntimeError("Set CLOUDFLARE_ACCOUNT_ID (32 hex characters) and CLOUDFLARE_API_TOKEN first")
            client = Cloudflare(account, token, args, requests)
            consecutive_unknown = 0
            for start in range(0, len(pending), args.batch_size):
                batch = pending[start:start + args.batch_size]
                check_batch(client, db, batch)
                marks = [db.execute("SELECT status FROM domains WHERE name=?", (n,)).fetchone()[0] for n in batch]
                consecutive_unknown = consecutive_unknown + 1 if all(s == "unknown" for s in marks) else 0
                render(db, run, "Checks in progress")
                available = db.execute("SELECT count(*) FROM domains WHERE status='available'").fetchone()[0]
                log(f"Processed {min(start + len(batch), len(pending))}/{len(pending)}; available: {available}; HTTP calls: {client.calls}")
                if consecutive_unknown >= 3:
                    raise StopRun("Three consecutive batches unresolved; checkpoint saved. Resume after checking connectivity/API access.")
            note = "Checking finished; inspect unknown and unsupported sections"
        else:
            note = "No valid candidates require checking; see retained results and invalid entries"
    except KeyboardInterrupt:
        note, code = "Interrupted; progress saved. Resume this run to continue.", 130
        log(note)
    except (OSError, RuntimeError, ValueError, sqlite3.Error) as exc:
        note, code = f"Stopped: {exc}", 1
        log(note)
    finally:
        try:
            if initialized:
                try:
                    counts = render(db, run, note, args.dry_run)
                    log(f"Report: {run / 'report.md'}")
                    log(" | ".join(f"{key}: {counts[key]}" for key in STATUSES))
                    if code == 0 and not args.dry_run and (counts["unknown"] or counts["unsupported"]):
                        code = 3
                    if counts["unknown"] or counts["unsupported"] or code == 130:
                        log(f"Resume: {sys.executable} domain_sieve.py --resume '{run}'")
                except (OSError, sqlite3.Error) as exc:
                    log(f"Could not update report: {exc}; checkpoint directory: {run}")
                    code = 1
        finally:
            if client:
                client.session.close()
            if db:
                db.close()
            if lock:
                lock.close()
    return code


if __name__ == "__main__":
    sys.exit(main())
