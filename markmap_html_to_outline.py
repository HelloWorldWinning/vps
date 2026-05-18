#!/usr/bin/env python3
from __future__ import annotations

"""
markmap_html_to_outline.py

Reverse a generated Markmap HTML file back into a text/Markdown outline.

Typical use:
  python3 markmap_html_to_outline.py a_markmap.html
  python3 markmap_html_to_outline.py a_markmap.html -o restored.txt
  cat a_markmap.html | python3 markmap_html_to_outline.py > restored.txt

Notes:
  - This reconstructs the outline from the embedded Markmap data object.
  - It cannot perfectly recover the exact original source text, comments, blank lines,
    frontmatter, or every Markdown formatting detail that was lost during rendering.
  - The default output is Markdown-style headings saved as .txt, which can be fed back
    into your forward Markmap renderer.
"""

import argparse
import html
import json
import re
import sys
import unicodedata
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable


BR = "\033[1;31m"
RS = "\033[0m"


# ─────────────────────────────────────────────────────────────
# Small HTML → readable text converter for node labels
# ─────────────────────────────────────────────────────────────


class InlineHtmlToText(HTMLParser):
    """Convert Markmap node HTML snippets into readable plain text."""

    BLOCK_TAGS = {
        "address",
        "article",
        "aside",
        "blockquote",
        "br",
        "dd",
        "div",
        "dl",
        "dt",
        "figcaption",
        "figure",
        "footer",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hr",
        "li",
        "main",
        "nav",
        "ol",
        "p",
        "pre",
        "section",
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "tr",
        "ul",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.link_stack: list[str | None] = []
        self.in_code = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()

        if tag in self.BLOCK_TAGS:
            self._soft_space()

        if tag == "a":
            href = None
            for key, value in attrs:
                if key.lower() == "href" and value:
                    href = value
                    break
            self.link_stack.append(href)

        if tag in {"code", "kbd", "samp"}:
            self.in_code += 1
            self.parts.append("`")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()

        if tag in {"code", "kbd", "samp"}:
            if self.in_code:
                self.in_code -= 1
            self.parts.append("`")

        if tag == "a":
            href = self.link_stack.pop() if self.link_stack else None
            if href:
                # Preserve the URL without trying to reconstruct exact Markdown syntax.
                current = "".join(self.parts).rstrip()
                if href not in current[-len(href) - 8 :]:
                    self.parts.append(f" ({href})")

        if tag in self.BLOCK_TAGS:
            self._soft_space()

    def handle_data(self, data: str) -> None:
        if data:
            self.parts.append(data)

    def handle_entityref(self, name: str) -> None:
        self.parts.append(html.unescape(f"&{name};"))

    def handle_charref(self, name: str) -> None:
        self.parts.append(html.unescape(f"&#{name};"))

    def _soft_space(self) -> None:
        if self.parts and not self.parts[-1].endswith((" ", "\n")):
            self.parts.append(" ")

    def get_text(self) -> str:
        value = "".join(self.parts)
        value = html.unescape(value)
        value = unicodedata.normalize("NFKC", value)
        value = value.replace("\u00a0", " ")
        value = re.sub(r"[\u200B-\u200D\uFEFF]", "", value)
        value = re.sub(r"\s+", " ", value).strip()
        return value


def html_fragment_to_text(value: Any) -> str:
    if value is None:
        return ""

    raw = str(value)

    if not raw:
        return ""

    parser = InlineHtmlToText()

    try:
        parser.feed(raw)
        parser.close()
        text = parser.get_text()
    except Exception:
        text = re.sub(r"<[^>]+>", " ", html.unescape(raw))
        text = re.sub(r"\s+", " ", text).strip()

    return text


# ─────────────────────────────────────────────────────────────
# JavaScript/JSON object extraction
# ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Candidate:
    start: int
    end: int
    text: str


def strip_html_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def iter_balanced_object_candidates(text: str) -> Iterable[Candidate]:
    """
    Yield balanced {...} substrings while respecting JS strings, template strings,
    regex-ish escapes, and comments. This is intentionally conservative.
    """

    stack: list[int] = []
    string_quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False

    i = 0
    n = len(text)

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if line_comment:
            if ch in "\r\n":
                line_comment = False
            i += 1
            continue

        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
                continue
            i += 1
            continue

        if string_quote is not None:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_quote:
                string_quote = None
            i += 1
            continue

        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue

        if ch in {'"', "'", "`"}:
            string_quote = ch
            escaped = False
            i += 1
            continue

        if ch == "{":
            stack.append(i)
            i += 1
            continue

        if ch == "}" and stack:
            start = stack.pop()
            end = i + 1
            candidate = text[start:end]

            # Cheap prefilter: Markmap nodes always have content/children-like keys.
            if "content" in candidate and ("children" in candidate or "payload" in candidate):
                yield Candidate(start=start, end=end, text=candidate)

        i += 1


def extract_script_bodies(html_text: str) -> list[str]:
    bodies = re.findall(
        r"<script\b[^>]*>(.*?)</script\s*>",
        html_text,
        flags=re.IGNORECASE | re.DOTALL,
    )

    # Include the full document as a fallback because some Markmap exporters inline
    # JSON outside normal script tags.
    bodies.append(html_text)
    return bodies


def parse_json_candidate(candidate: str) -> Any | None:
    """Parse strict JSON first; try small JS-literal repairs second."""

    candidate = candidate.strip()

    try:
        return json.loads(candidate)
    except Exception:
        pass

    repaired = candidate

    # Remove trailing commas before } or ].
    repaired = re.sub(r",\s*([}\]])", r"\1", repaired)

    # Quote simple unquoted object keys. This intentionally does not attempt to
    # support arbitrary JavaScript expressions.
    repaired = re.sub(
        r"([{,]\s*)([A-Za-z_$][\w$-]*)(\s*:)",
        lambda m: f'{m.group(1)}"{m.group(2)}"{m.group(3)}',
        repaired,
    )

    # Convert single-quoted strings when they do not contain double quotes.
    # Good enough for simple Markmap variants; strict JSON path is preferred.
    def replace_single_quoted(match: re.Match[str]) -> str:
        body = match.group(1)
        if '"' in body:
            return match.group(0)
        body = body.replace('\\\'', "'")
        return json.dumps(body)

    repaired = re.sub(r"'((?:\\.|[^'\\])*)'", replace_single_quoted, repaired)

    try:
        return json.loads(repaired)
    except Exception:
        return None


def is_markmap_node(value: Any) -> bool:
    if not isinstance(value, dict):
        return False

    has_content = "content" in value or "text" in value or "label" in value or "title" in value
    children = value.get("children")

    if has_content and isinstance(children, list):
        return True

    if has_content and "payload" in value:
        return True

    return False


def score_node(node: Any) -> int:
    if not isinstance(node, dict):
        return 0

    score = 0

    if "content" in node:
        score += 20
    if isinstance(node.get("children"), list):
        score += 20 + len(node.get("children") or [])
    if "payload" in node:
        score += 5

    for child in node.get("children") or []:
        score += score_node(child)

    return score


def find_node_in_value(value: Any) -> Any | None:
    """Find the best Markmap-looking node inside parsed JSON."""

    best: Any | None = None
    best_score = 0

    def visit(item: Any) -> None:
        nonlocal best, best_score

        if is_markmap_node(item):
            current_score = score_node(item)
            if current_score > best_score:
                best = item
                best_score = current_score

        if isinstance(item, dict):
            for child_value in item.values():
                visit(child_value)
        elif isinstance(item, list):
            for child_value in item:
                visit(child_value)

    visit(value)
    return best


def extract_markmap_root(html_text: str) -> dict[str, Any]:
    html_text = strip_html_comments(html_text)

    candidates: list[tuple[int, dict[str, Any]]] = []

    for body in extract_script_bodies(html_text):
        for candidate in iter_balanced_object_candidates(body):
            parsed = parse_json_candidate(candidate.text)
            if parsed is None:
                continue

            node = find_node_in_value(parsed)
            if isinstance(node, dict):
                candidates.append((score_node(node), node))

    if not candidates:
        raise ValueError(
            "Could not find embedded Markmap data. The HTML may not be a static "
            "Markmap export, or its data may be encoded in an unsupported format."
        )

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


# ─────────────────────────────────────────────────────────────
# Outline reconstruction
# ─────────────────────────────────────────────────────────────


def get_node_label(node: dict[str, Any]) -> str:
    for key in ("content", "text", "label", "title"):
        value = node.get(key)
        if value:
            text = html_fragment_to_text(value)
            if text:
                return text

    payload = node.get("payload")
    if isinstance(payload, dict):
        for key in ("text", "label", "title"):
            value = payload.get(key)
            if value:
                text = html_fragment_to_text(value)
                if text:
                    return text

    return "Untitled"


def get_children(node: dict[str, Any]) -> list[dict[str, Any]]:
    children = node.get("children")

    if not isinstance(children, list):
        return []

    return [child for child in children if isinstance(child, dict)]


def render_markdown_outline(root: dict[str, Any]) -> str:
    lines: list[str] = []

    root_label = get_node_label(root)
    root_children = get_children(root)

    # Markmap often uses an empty synthetic root. Do not emit it.
    emit_root = bool(root_label and root_label.lower() not in {"root", "untitled"})

    def emit(node: dict[str, Any], level: int) -> None:
        label = get_node_label(node)
        heading_level = max(1, min(level, 6))
        lines.append(f"{'#' * heading_level} {label}".rstrip())

        for child in get_children(node):
            emit(child, level + 1)

    if emit_root:
        emit(root, 1)
    else:
        for child in root_children:
            emit(child, 1)

    return "\n".join(lines).rstrip() + "\n"


def render_indented_outline(root: dict[str, Any], indent_size: int = 2) -> str:
    lines: list[str] = []
    unit = " " * max(1, indent_size)

    root_label = get_node_label(root)
    root_children = get_children(root)
    emit_root = bool(root_label and root_label.lower() not in {"root", "untitled"})

    def emit(node: dict[str, Any], depth: int) -> None:
        label = get_node_label(node)
        lines.append(f"{unit * depth}- {label}".rstrip())

        for child in get_children(node):
            emit(child, depth + 1)

    if emit_root:
        emit(root, 0)
    else:
        for child in root_children:
            emit(child, 0)

    return "\n".join(lines).rstrip() + "\n"


def render_plain_outline(root: dict[str, Any], indent_size: int = 2) -> str:
    lines: list[str] = []
    unit = " " * max(1, indent_size)

    root_label = get_node_label(root)
    root_children = get_children(root)
    emit_root = bool(root_label and root_label.lower() not in {"root", "untitled"})

    def emit(node: dict[str, Any], depth: int) -> None:
        label = get_node_label(node)
        lines.append(f"{unit * depth}{label}".rstrip())

        for child in get_children(node):
            emit(child, depth + 1)

    if emit_root:
        emit(root, 0)
    else:
        for child in root_children:
            emit(child, 0)

    return "\n".join(lines).rstrip() + "\n"


def render_outline(root: dict[str, Any], output_format: str, indent_size: int) -> str:
    if output_format == "markdown":
        return render_markdown_outline(root)

    if output_format == "indent":
        return render_indented_outline(root, indent_size=indent_size)

    if output_format == "plain":
        return render_plain_outline(root, indent_size=indent_size)

    raise ValueError(f"Unsupported format: {output_format}")


# ─────────────────────────────────────────────────────────────
# File handling
# ─────────────────────────────────────────────────────────────


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def write_text(path: Path, text: str, overwrite: bool = False) -> None:
    if path.exists() and not overwrite:
        raise FileExistsError(f"Output already exists: {path}. Use --overwrite to replace it.")

    path.write_text(text, encoding="utf-8")


def make_output_path(input_path: Path, suffix: str = "_outline", extension: str = ".txt") -> Path:
    if input_path.suffix.lower() in {".html", ".htm"}:
        return input_path.with_name(f"{input_path.stem}{suffix}{extension}")

    return input_path.with_name(f"{input_path.name}{suffix}{extension}")


def convert_html_text(html_text: str, output_format: str, indent_size: int) -> str:
    root = extract_markmap_root(html_text)
    return render_outline(root, output_format=output_format, indent_size=indent_size)


def convert_file(
    input_path: Path,
    output_path: Path | None,
    output_format: str,
    indent_size: int,
    overwrite: bool,
) -> Path:
    input_path = input_path.expanduser().resolve()

    if not input_path.is_file():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    html_text = read_text(input_path)
    outline = convert_html_text(html_text, output_format=output_format, indent_size=indent_size)

    final_output = output_path.expanduser().resolve() if output_path else make_output_path(input_path)
    write_text(final_output, outline, overwrite=overwrite)
    return final_output


# ─────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reverse a generated Markmap HTML file back into a text/Markdown outline."
    )

    parser.add_argument(
        "html_files",
        nargs="*",
        help="Generated .html/.htm Markmap file(s). If omitted, HTML is read from stdin.",
    )

    parser.add_argument(
        "-o",
        "--output",
        help="Output .txt file path. Only valid when converting one input file.",
    )

    parser.add_argument(
        "--format",
        choices=["markdown", "indent", "plain"],
        default="markdown",
        help="Output style. Default: markdown.",
    )

    parser.add_argument(
        "--indent-size",
        type=int,
        default=2,
        help="Spaces per nesting level for --format indent/plain. Default: 2.",
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing output files.",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.output and len(args.html_files) != 1:
        parser.error("--output can only be used with exactly one input file.")

    try:
        if not args.html_files:
            html_text = sys.stdin.read()
            if not html_text.strip():
                raise SystemExit("No HTML received on stdin.")

            outline = convert_html_text(
                html_text,
                output_format=args.format,
                indent_size=args.indent_size,
            )

            if args.output:
                output_path = Path(args.output).expanduser().resolve()
                write_text(output_path, outline, overwrite=args.overwrite)
                print(f"[✓] stdin → {BR}{output_path}{RS}", file=sys.stderr)
            else:
                sys.stdout.write(outline)

            return 0

        for raw_path in args.html_files:
            input_path = Path(raw_path)
            output_path = Path(args.output) if args.output else None

            final_output = convert_file(
                input_path=input_path,
                output_path=output_path,
                output_format=args.format,
                indent_size=args.indent_size,
                overwrite=args.overwrite,
            )

            print(f"[✓] {input_path} → {BR}{final_output}{RS}")

        return 0

    except Exception as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
