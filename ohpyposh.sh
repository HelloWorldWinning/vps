#!/usr/bin/env bash
# ohpyposh.sh — install / refresh the gmay3 oh-my-posh prompt on a new oh-my-posh core.
#
# What changed vs the previous version of this script:
#   1. set_poshcontext now exports POSH_DIR_PARENT / POSH_DIR_BASE / POSH_DIR_COUNT /
#      POSH_DIR_FLAG — the four variables gmay3.omp.json_for_new_oh_my_posh actually
#      reads. The old script exported a single POSH_DIR_INFO, which no template used,
#      so the path / file count / flag rendered empty.
#   2. set_poshcontext is sourced AFTER `oh-my-posh init bash`. `oh-my-posh init bash`
#      emits its own `function set_poshcontext() { return; }` stub, so a definition
#      placed before the init line is silently overwritten.
#   3. The flag is built from raw UTF-8 bytes instead of printf '\U...', which only
#      works under a UTF-8 locale.
#
# Safe to re-run. Everything it puts in ~/.bashrc lives between the BEGIN/END markers
# below and is replaced on each run; ~/.bashrc is backed up and syntax-checked first.

set -u

RAW="https://raw.githubusercontent.com/HelloWorldWinning/vps/main"
THEMES="$HOME/themes"
CONFIG="$THEMES/gmay3.omp.json"
CONTEXT="$THEMES/poshcontext.sh"
BASHRC="$HOME/.bashrc"

# --------------------------------------------------------------------------- deps
if command -v apt >/dev/null 2>&1; then
	apt install -y unzip jq wget curl
fi

mkdir -p "$THEMES"

# ------------------------------------------------------------------- theme + tools
wget --inet4-only -q -O "$CONFIG" "$RAW/gmay3.omp.json_for_new_oh_my_posh" &&
	echo "downloaded $CONFIG" || echo "WARNING: could not download $CONFIG" >&2

wget --inet4-only -q -O "$THEMES/hostname_length_adjuster.sh" "$RAW/hostname_length_adjuster.sh"
wget --inet4-only -q -O "$THEMES/cpu_usage.sh" "$RAW/cpu_usage.sh"
wget --inet4-only -q -O "$THEMES/update_prompt_date_DD_Day.sh" "$RAW/update_prompt_date_DD_Day.sh"
chmod +x "$THEMES/update_prompt_date_DD_Day.sh"
# That script hardcodes config_file=/root/themes/gmay3.omp.json; point it at this $HOME.
sed -i "s#^config_file=.*#config_file=\"$CONFIG\"#" "$THEMES/update_prompt_date_DD_Day.sh"

# Country code, cached — set_poshcontext turns it into the flag. Done here too so the
# verification at the end works on a brand-new host.
CC_FILE="$HOME/.country_code"
CC=""
[ -r "$CC_FILE" ] && CC="$(tr -d '[:space:]' <"$CC_FILE")"
case "$CC" in
[A-Z][A-Z]) ;;
*)
	CC="$(curl -fsS --connect-timeout 5 --max-time 10 'http://ip-api.com/line/?fields=countryCode' 2>/dev/null | tr -d '[:space:]')"
	case "$CC" in
	[A-Z][A-Z]) printf '%s\n' "$CC" >"$CC_FILE" ;;
	*) echo "WARNING: country code lookup failed; flag falls back to ' Unknown '" >&2 ;;
	esac
	;;
esac

# -------------------------------------------------------------- prompt context file
cat >"$CONTEXT" <<'CTX'
# gmay3 prompt context — feeds gmay3.omp.json (oh-my-posh v3 schema).
#
# MUST be sourced AFTER `eval "$(oh-my-posh init bash ...)"`:
# the init script defines its own `function set_poshcontext() { return; }` stub and
# would overwrite this definition if this file were sourced first.
#
# Exported variables and the template fields that read them:
#   POSH_DIR_PARENT   <i>{{ .Env.POSH_DIR_PARENT }}</i>    parent dir, trailing slash
#   POSH_DIR_BASE     <b>{{ .Env.POSH_DIR_BASE }}</b>      current dir name
#   POSH_DIR_COUNT    {{ .Env.POSH_DIR_COUNT }}            visible entries in $PWD
#   POSH_DIR_FLAG     {{ .Env.POSH_DIR_FLAG }}             country flag + 2 spaces
#   POSH_PYTHON_INFO  {{ .Env.POSH_PYTHON_INFO }}          "<conda env> <python ver>"
#   POSH_WEATHER      {{ .Env.POSH_WEATHER }}              ~/.weather_temperature

function set_poshcontext() {
    # --- directory: parent, basename, entry count -------------------------------
    local pwd_path parent_dir parent base count
    pwd_path="$PWD"
    if [ "$pwd_path" = "/" ]; then
        parent="/"
        base=""
    else
        parent_dir="$(dirname "$pwd_path")"
        if [ "$parent_dir" = "/" ]; then
            parent="/"
        else
            parent="${parent_dir}/"
        fi
        base="$(basename "$pwd_path")"
    fi
    count="$(ls -1 2>/dev/null | wc -l | tr -d ' ')"

    export POSH_DIR_PARENT="$parent"
    export POSH_DIR_BASE="$base"
    export POSH_DIR_COUNT="$count"

    # --- country flag: computed once per shell, locale-independent ---------------
    # Regional indicators U+1F1E6..U+1F1FF are UTF-8 F0 9F 87 A6..BF, so the emoji is
    # emitted as raw bytes. printf '\U0001F1FA' only works under a UTF-8 locale.
    if [ -z "${POSH_DIR_FLAG:-}" ]; then
        local cc c1 c2 b1 b2
        cc="$(printf '%s' "${country_code:-}" | tr -d '[:space:]')"
        if [ ${#cc} -eq 2 ]; then
            c1=$(printf '%d' "'${cc%?}")
            c2=$(printf '%d' "'${cc#?}")
            b1=$(( 0xA6 + c1 - 65 ))
            b2=$(( 0xA6 + c2 - 65 ))
            export POSH_DIR_FLAG="$(printf "\xF0\x9F\x87\x$(printf %02X $b1)\xF0\x9F\x87\x$(printf %02X $b2)")  "
        else
            export POSH_DIR_FLAG=" Unknown  "
        fi
    fi

    # --- conda env + python version ---------------------------------------------
    local python_version conda_env
    python_version="$(command -v python >/dev/null 2>&1 && python --version 2>&1 | awk '{print $2}' || echo '')"
    conda_env="${CONDA_DEFAULT_ENV:-}"
    if [ -z "$conda_env" ] && [ -z "$python_version" ]; then
        export POSH_PYTHON_INFO=""
    else
        export POSH_PYTHON_INFO="${conda_env} ${python_version}"
    fi

    # --- weather -----------------------------------------------------------------
    if [ -f "$HOME/.weather_temperature" ]; then
        export POSH_WEATHER="$(cat "$HOME/.weather_temperature")"
    else
        export POSH_WEATHER=""
    fi
}
CTX
echo "wrote $CONTEXT"

# ------------------------------------------------------------------ oh-my-posh core
curl -4s https://ohmyposh.dev/install.sh | bash -s
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
command -v oh-my-posh >/dev/null 2>&1 && oh-my-posh --version

# ------------------------------------------------------------------------- ~/.bashrc
[ -f "$BASHRC" ] || touch "$BASHRC"
BACKUP="$BASHRC.bak.$(date +%Y%m%d%H%M%S)"
cp "$BASHRC" "$BACKUP"

# Remove: our managed block, the marker block written by the old installer, any
# stray `function set_poshcontext() { ... }`, its misleading comment banner, stray
# oh-my-posh init lines and stray poshcontext sources. Legacy country_code code is
# left alone — it is harmless, and our block re-exports country_code after it.
awk '
{ L[++n] = $0 }
END {
    for (i = 1; i <= n; i++) {
        s = L[i]
        if (s ~ /^# BEGIN (gmay3-prompt-v2|country-code-weather-v2)$/) {
            del[i] = 1
            for (j = i + 1; j <= n; j++) { del[j] = 1; if (L[j] ~ /^# END /) { i = j; break } }
            continue
        }
        if (s ~ /^[ \t]*function[ \t]+set_poshcontext\(\)/) {
            del[i] = 1
            for (j = i + 1; j <= n; j++) { del[j] = 1; if (L[j] ~ /^\}[ \t]*$/) { i = j; break } }
            continue
        }
        if (s ~ /Add this function to your/) {
            del[i] = 1
            if (i > 1 && L[i-1] ~ /^#[ \t]*=+[ \t]*$/) del[i-1] = 1
            if (L[i+1] ~ /^#[ \t]*=+[ \t]*$/) del[i+1] = 1
            continue
        }
        if (s ~ /^[ \t]*eval .*oh-my-posh init/)  { del[i] = 1; continue }
        if (s ~ /^[ \t]*(source|\.) .*poshcontext\.sh/) { del[i] = 1; continue }
    }
    for (i = 1; i <= n; i++) if (!del[i]) print L[i]
}
' "$BACKUP" >"$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"

cat >>"$BASHRC" <<'EOF'

# BEGIN gmay3-prompt-v2
# Managed by ohpyposh.sh — this whole block is rewritten on every run.
case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) PATH="$HOME/.local/bin:$PATH" ;;
esac

# Country code (cached in ~/.country_code) — set_poshcontext turns it into the flag.
country_code_file="$HOME/.country_code"
country_code=""
if [ -r "$country_code_file" ]; then
	country_code="$(tr -d '[:space:]' <"$country_code_file")"
fi
case "$country_code" in
[A-Z][A-Z]) ;;
*)
	country_code="$(curl -fsS --connect-timeout 5 --max-time 10 'http://ip-api.com/line/?fields=countryCode' 2>/dev/null | tr -d '[:space:]')"
	case "$country_code" in
	[A-Z][A-Z]) printf '%s\n' "$country_code" >"$country_code_file" ;;
	*) country_code="" ;;
	esac
	;;
esac
export country_code
alias wea='source <(curl -fsSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh)'

# 1) oh-my-posh core.
if command -v oh-my-posh >/dev/null 2>&1; then
	eval "$(oh-my-posh init bash --config "$HOME/themes/gmay3.omp.json")"
fi

# 2) Prompt context. MUST stay below the init line above: `oh-my-posh init bash`
#    emits a `function set_poshcontext() { return; }` stub that would win otherwise.
if [ -r "$HOME/themes/poshcontext.sh" ]; then
	source "$HOME/themes/poshcontext.sh"
fi
# END gmay3-prompt-v2
EOF

if bash -n "$BASHRC"; then
	echo "~/.bashrc updated (backup: $BACKUP)"
else
	cp "$BACKUP" "$BASHRC"
	echo "ERROR: generated ~/.bashrc failed syntax check — restored from $BACKUP" >&2
	exit 1
fi

# ----------------------------------------------------------------------------- cron
LOCK_FILE="/tmp/prompt_update.lock"
CRON_DATE="*/1 * * * * /usr/bin/flock -n $LOCK_FILE $THEMES/update_prompt_date_DD_Day.sh"
CRON_WEA="*/30 * * * * curl -sSL $RAW/weather_temperature.sh | bash"

{
	crontab -l 2>/dev/null | grep -v 'update_prompt_date_DD_Day.sh' | grep -v 'weather_temperature.sh'
	echo "$CRON_DATE"
	echo "$CRON_WEA"
} | crontab -
echo "--- crontab ---"
crontab -l

# --------------------------------------------------------------------- first run
curl -sSL "$RAW/weather_temperature.sh" | bash
bash "$THEMES/update_prompt_date_DD_Day.sh"

# ------------------------------------------------------------------------- verify
echo "--- verify: context variables ---"
country_code="$CC" bash -c "
source '$CONTEXT'
set_poshcontext
printf 'POSH_DIR_PARENT=[%s]\nPOSH_DIR_BASE=[%s]\nPOSH_DIR_COUNT=[%s]\nPOSH_DIR_FLAG=[%s]\nPOSH_PYTHON_INFO=[%s]\nPOSH_WEATHER=[%s]\n' \
  \"\$POSH_DIR_PARENT\" \"\$POSH_DIR_BASE\" \"\$POSH_DIR_COUNT\" \"\$POSH_DIR_FLAG\" \"\$POSH_PYTHON_INFO\" \"\$POSH_WEATHER\"
"

echo "--- verify: rendered prompt ---"
country_code="$CC" bash -c "
source '$CONTEXT'
set_poshcontext
oh-my-posh print primary --shell=bash --config '$CONFIG'
" | sed 's/\\\[[^]]*\\\]//g'
echo
echo "Every POSH_* value above must be non-empty, and the rendered line must show"
echo "path, file count and flag. Then reload the shell:  exec bash -l"
