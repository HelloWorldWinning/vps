#!/usr/bin/env bash
# Save a clean IPQuality report for the available public IP families.
set -euo pipefail
umask 077

fail() {
    printf 'IPQuality: %s\n' "$*" >&2
    exit 1
}

for command in curl jq bc nc dig python3; do
    command -v "$command" >/dev/null 2>&1 || fail "Missing dependency: $command"
done

# Use China Standard Time and English day names in the filename.
stamp=$(LC_ALL=C TZ=Asia/Shanghai date '+%Y-%m-%d_%H-%M-%S_%p_%a')
output_dir=$(cd -- "$HOME" && pwd -P)
workdir=$(mktemp -d "$output_dir/.ip_quality.XXXXXXXX")
check_pid=
progress_pid=
cleanup() {
    if [[ -n $progress_pid ]]; then
        kill "$progress_pid" 2>/dev/null || true
    fi
    if [[ -n $check_pid ]]; then
        kill "$check_pid" 2>/dev/null || true
    fi
    rm -rf -- "$workdir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Downloading IPQuality…\n' >&2
curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 60 \
    --output "$workdir/ipquality.sh" https://IP.Check.Place \
    || fail "Could not download the upstream script."
[[ -s "$workdir/ipquality.sh" ]] || fail "The upstream download was empty."

printf 'Checking IPv4 and IPv6…\n' >&2
started=$SECONDS
# Export structured data while capturing online-report links from stdout.
TERM=dumb bash "$workdir/ipquality.sh" -l cn -n -o "$workdir/upstream.json" \
    </dev/null >"$workdir/console.log" 2>/dev/null &
check_pid=$!
(
    while sleep 5 >/dev/null 2>&1; do
        printf 'IPQuality still running (%ds elapsed)…\n' "$((SECONDS - started))" >&2
    done
) &
progress_pid=$!

status=0
wait "$check_pid" || status=$?
check_pid=
kill "$progress_pid" 2>/dev/null || true
wait "$progress_pid" 2>/dev/null || true
progress_pid=

[[ -s "$workdir/upstream.json" ]] || fail "No JSON report was produced (upstream exit $status)."
printf 'Rendering HTML and saving JSON…\n' >&2

family=$(python3 - "$workdir" <<'PY_RENDER'
import ipaddress
import json
import re
import sys
from html import escape
from pathlib import Path

work = Path(sys.argv[1])
ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
link_pattern = re.compile(r"^\s*报告链接[：:]\s*(https://report\.check\.place/ip/[a-z0-9_-]+\.svg)\s*$", re.I)

def load_reports(path):
    # Upstream appends one standalone JSON object per detected family.
    source = path.read_text(encoding="utf-8-sig")
    decoder = json.JSONDecoder()
    records = []
    offset = 0
    while (next_value := re.search(r"\S", source[offset:])) is not None:
        start = offset + next_value.start()
        value, offset = decoder.raw_decode(source, start)
        records.extend(value if isinstance(value, list) else [value])
    if not records or any(not isinstance(record, dict) or not record for record in records):
        raise ValueError("No usable IPQuality records")
    return records

def ip_family(record):
    head = record.get("Head")
    address = head.get("IP", "") if isinstance(head, dict) else ""
    if isinstance(address, str):
        try:
            return ipaddress.ip_address(address.strip().replace("*", "0")).version
        except ValueError:
            # Some upstream versions shorten the masked IPv6 heading.
            if ":" in address and re.fullmatch(r"[0-9a-f:*]+", address, re.I):
                return 6
    return None

def flatten(value, path=()):
    if isinstance(value, dict) and value:
        for key, child in value.items():
            yield from flatten(child, path + (key,))
    else:
        yield path, value

labels = {
    "Head": "检测信息", "Info": "基础信息", "Type": "类型",
    "Score": "风险评分", "Factor": "风险因子", "Media": "流媒体及 AI 服务",
    "Mail": "邮件连通性及黑名单", "IP": "IP 地址", "Time": "报告时间",
    "Version": "脚本版本", "Organization": "组织", "TimeZone": "时区",
    "Status": "状态", "Region": "地区", "Port25": "本地 25 端口出站",
}

def cell(value):
    if value is None or value in ("", "null"):
        return '<span class="missing">—</span>'
    if isinstance(value, bool):
        return "是" if value else "否"
    if isinstance(value, (list, dict)):
        value = json.dumps(value, ensure_ascii=False)
    return escape(str(value))

def table(title, columns, headings):
    rows = []
    for path in dict.fromkeys(path for column in columns for path in column):
        label = " / ".join(labels.get(key, key) for key in path) or "值"
        values = "".join(f"<td>{cell(column.get(path))}</td>" for column in columns)
        rows.append(f'<tr><th scope="row">{escape(label)}</th>{values}</tr>')
    header = "".join(f'<th scope="col">{escape(heading)}</th>' for heading in headings)
    return (f"<section><h2>{escape(title)}</h2><div class=\"table-wrap\"><table>"
            f'<thead><tr><th scope="col">项目</th>{header}</tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div></section>')

try:
    records = load_reports(work / "upstream.json")
except (OSError, ValueError) as error:
    sys.exit(f"IPQuality: could not read the upstream JSON export: {error}")

families = [ip_family(record) for record in records]
headings = [f"IPv{family}" if family else f"检测结果 {i}"
            for i, family in enumerate(families, 1)]
prefix = {frozenset({4}): "ipv4", frozenset({6}): "ipv6",
          frozenset({4, 6}): "ipv4_v6"}.get(frozenset(families), "ip")
sections = dict.fromkeys(key for record in records for key in record)
tables = []
for section in sections:
    columns = [dict(flatten(record[section])) if section in record else {} for record in records]
    title = "IP 类型属性" if section == "Type" else labels.get(section, section)
    tables.append(table(title, columns, headings))

console = ansi.sub("", (work / "console.log").read_text(encoding="utf-8", errors="replace"))
links = dict.fromkeys(match[1] for line in console.splitlines() if (match := link_pattern.fullmatch(line)))
footer = ""
if links:
    items = "".join(f'<li><a href="{escape(url)}">{escape(url)}</a></li>' for url in links)
    footer = f"<section><h2>在线报告链接</h2><ul>{items}</ul></section>"
notice = "<p>有检测结果无法识别 IP 版本，原始字段已保留。</p>" if None in families else ""

page = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IP 质量检测报告</title>
<style>
:root {{ color-scheme: light dark; font-family: system-ui, sans-serif; }}
body {{ max-width: 68rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.55; }}
section {{ margin-block: 2rem; }}
h2 {{ font-size: 1.2rem; }}
.table-wrap {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; text-align: left; }}
th, td {{ border-bottom: 1px solid GrayText; padding: .45rem .75rem; overflow-wrap: anywhere; }}
tbody th {{ font-weight: 500; }}
thead {{ background: CanvasText; color: Canvas; }}
.missing {{ color: GrayText; }}
a {{ overflow-wrap: anywhere; }}
</style>
</head>
<body><main>
<h1>IP 质量检测报告</h1>
{notice}
{"".join(tables)}
{footer}
</main></body></html>
"""
(work / "report.html").write_text(page, encoding="utf-8")
(work / "report.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(prefix)
PY_RENDER
) || fail "Could not render the report."

base="$output_dir/${family}_quality_$stamp"
suffix=1
while :; do
    candidate=$base
    if ((suffix > 1)); then
        candidate="${base}_$suffix"
    fi
    if [[ ! -e "$candidate.html" && ! -L "$candidate.html" ]] &&
        ln -T -- "$workdir/report.json" "$candidate.json" 2>/dev/null; then
        if ln -T -- "$workdir/report.html" "$candidate.html"; then
            break
        fi
        rm -- "$candidate.json"
        fail "Could not save $candidate.html"
    fi
    [[ -e "$candidate.json" || -L "$candidate.json" || -e "$candidate.html" || -L "$candidate.html" ]] \
        || fail "Could not save $candidate.json"
    ((suffix += 1))
done

if ((status != 0)); then
    printf 'IPQuality exited with status %s. Saved the available report data.\n' "$status" >&2
fi
printf '%s\n' "$candidate.html"
