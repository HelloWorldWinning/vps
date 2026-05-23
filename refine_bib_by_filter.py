#!/usr/bin/env python3
"""
Filter a BibTeX file by keyword/phrase lines.

Usage:
    ./refine_bib_by_filter.py 601.bib filter.txt
    ./refine_bib_by_filter.py 601.bib filter.txt -o 601.filtered.txt
    ./refine_bib_by_filter.py 601.bib filter.txt -r
    ./refine_bib_by_filter.py 601.bib filter.txt -r -o 601.remaining.txt

Behavior:
    - Each non-empty, non-comment line in filter.txt is one filter item.
    - Default mode keeps each BibTeX entry that matches at least one filter item.
    - Reverse mode (-r/--reverse) drops each BibTeX entry that matches at least
      one filter item, and writes only the entries that match none of them.
    - Matching is case-insensitive and punctuation-insensitive:
      "state-space model" matches "state space model".
    - Output defaults to <input_stem>.filtered.txt.
"""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from typing import List, Sequence, Tuple


def normalize_text(text: str) -> str:
    """Normalize text for robust phrase matching."""
    text = unicodedata.normalize("NFKC", text).lower()
    # Treat punctuation, hyphens, slashes, underscores, braces, etc. as spaces.
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def read_filter_items(path: Path) -> List[Tuple[str, str]]:
    """Return [(original_filter_line, normalized_filter_line), ...]."""
    items: List[Tuple[str, str]] = []
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            normalized = normalize_text(line)
            if normalized:
                items.append((line, normalized))

    if not items:
        raise ValueError(f"No usable filter items found in {path}")
    return items


def split_bibtex_entries(text: str) -> List[str]:
    """
    Split BibTeX text into top-level @...{...} or @...( ... ) entries.

    This lightweight parser is designed for filtering/export. It preserves each
    entry exactly as text and handles nested braces in fields.
    """
    entries: List[str] = []
    n = len(text)
    i = 0

    while i < n:
        at = text.find("@", i)
        if at == -1:
            break

        # Find opening delimiter for the BibTeX entry.
        j = at + 1
        while j < n and text[j] not in "{(":
            j += 1
        if j >= n:
            break

        open_delim = text[j]
        close_delim = "}" if open_delim == "{" else ")"
        depth = 1
        k = j + 1

        while k < n and depth > 0:
            ch = text[k]
            if ch == open_delim:
                depth += 1
            elif ch == close_delim:
                depth -= 1
            k += 1

        if depth != 0:
            # Malformed final entry. Keep the rest rather than silently dropping it.
            entries.append(text[at:].strip())
            break

        entries.append(text[at:k].strip())
        i = k

    return [entry for entry in entries if entry]


def matched_filters(entry: str, filters: Sequence[Tuple[str, str]]) -> List[str]:
    """Return original filter lines that match this BibTeX entry."""
    normalized_entry = f" {normalize_text(entry)} "
    matches: List[str] = []
    for original, normalized in filters:
        # Pad with spaces so one-word filters match as whole tokens after normalization.
        if f" {normalized} " in normalized_entry:
            matches.append(original)
    return matches


def default_output_path(bib_path: Path) -> Path:
    return bib_path.with_name(f"{bib_path.stem}.filtered.txt")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Filter BibTeX entries using keyword/phrase lines from a filter file. "
            "Default mode keeps matching entries; -r/--reverse drops matching entries."
        )
    )
    parser.add_argument("bib_file", type=Path, help="Input .bib file, e.g. 601.bib")
    parser.add_argument(
        "filter_file", type=Path, help="Filter file: one keyword/phrase per line"
    )
    parser.add_argument(
        "-r",
        "--reverse",
        action="store_true",
        help=(
            "Reverse mode: drop BibTeX entries that match at least one filter item, "
            "and write only entries with no matches."
        ),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output file. Default: <input_stem>.filtered.txt",
    )
    parser.add_argument(
        "--report-matches",
        action="store_true",
        help=(
            "Print matched filter item(s). In default mode, reports kept matching entries; "
            "in reverse mode, reports dropped matching entries."
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    bib_path: Path = args.bib_file
    filter_path: Path = args.filter_file
    output_path: Path = args.output or default_output_path(bib_path)

    if not bib_path.exists():
        print(f"ERROR: BibTeX file not found: {bib_path}", file=sys.stderr)
        return 2
    if not filter_path.exists():
        print(f"ERROR: filter file not found: {filter_path}", file=sys.stderr)
        return 2

    try:
        filters = read_filter_items(filter_path)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    bib_text = bib_path.read_text(encoding="utf-8", errors="replace")
    entries = split_bibtex_entries(bib_text)
    if not entries:
        print(f"ERROR: no BibTeX entries found in {bib_path}", file=sys.stderr)
        return 2

    kept: List[str] = []
    dropped: List[str] = []
    match_counter: Counter[str] = Counter()

    for entry in entries:
        matches = matched_filters(entry, filters)
        has_match = bool(matches)

        if args.reverse:
            should_keep = not has_match
            report_label = "DROP"
        else:
            should_keep = has_match
            report_label = "KEEP"

        if should_keep:
            kept.append(entry)
        else:
            dropped.append(entry)

        # Count/report the entries that matched filters, whether they are kept
        # in default mode or dropped in reverse mode.
        if has_match:
            match_counter.update(matches)
            if args.report_matches and report_label == (
                "DROP" if args.reverse else "KEEP"
            ):
                first_line = entry.splitlines()[0].strip()
                print(f"{report_label} {first_line}  <-- {', '.join(matches)}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")

    print(
        f"Mode          : {'drop matching entries (-r)' if args.reverse else 'keep matching entries'}"
    )
    print(f"Input entries : {len(entries)}")
    print(f"Kept entries  : {len(kept)}")
    print(f"Dropped       : {len(dropped)}")
    print(f"Filter items  : {len(filters)}")
    print(f"Output file   : {output_path}")

    if match_counter:
        print("\nTop matched filter items:")
        for item, count in match_counter.most_common(20):
            print(f"  {count:4d}  {item}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
