#!/usr/bin/env bash
# install-ds.sh — install an isolated `ds` launcher for Claude Code + DeepSeek.
#
# `ds` shares only the Claude Code executable and the current project files.
# Its user configuration, history, plugins, credentials, runtime settings, and
# logs live under DS_HOME (default: ~/.ds), not ~/.claude or ~/.claude.json.
#
# ---------------------------------------------------------------------------
# EDIT THIS BLOCK WHEN DEEPSEEK RELEASES OR RENAMES MODELS, THEN RERUN THIS SCRIPT.
# ---------------------------------------------------------------------------

# DeepSeek endpoints and default launcher behavior.
DEEPSEEK_ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
DEEPSEEK_MODELS_URL="https://api.deepseek.com/models"
DEEPSEEK_BALANCE_URL="https://api.deepseek.com/user/balance"
DS_DEFAULT_PROFILE="slots"       # slots | pro | flash
DS_SLOTS_START_ALIAS="opus"      # opus | sonnet | haiku | fable

# DeepSeek currently ships exactly two models:
#   deepseek-v4-pro    1.6T/49B MoE, 1M context — heavy reasoning and coding
#   deepseek-v4-flash  284B/13B MoE, 1M context — fast and cheap
#
# Claude Code aliases used by `ds --profile slots`.
# The slots profile deliberately keeps opus = pro and everything else = flash,
# so `/model opus` and `/model sonnet` are a real pro/flash switch in-session.
ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="DeepSeek V4 Pro"

ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash"
ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="DeepSeek V4 Flash"

ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="DeepSeek V4 Flash"

ANTHROPIC_DEFAULT_FABLE_MODEL="deepseek-v4-flash"
ANTHROPIC_DEFAULT_FABLE_MODEL_NAME="DeepSeek V4 Flash"

CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"

# Direct profiles. Each direct profile pins every Claude Code model slot,
# including background tasks and subagents, to one DeepSeek model.
DS_MODEL_PRO="$ANTHROPIC_DEFAULT_OPUS_MODEL"
DS_MODEL_FLASH="deepseek-v4-flash"

# Context windows used by Claude Code auto-compaction.
# Both V4 models are documented at 1M context.
DS_CONTEXT_PRO="1048576"
DS_CONTEXT_FLASH="1048576"
# Mixed-slot mode must use the smallest context among all mapped models.
DS_CONTEXT_SLOTS="1048576"

# Thinking mode per profile: on | off | auto.
# DeepSeek V4 supports both thinking and non-thinking modes on both models,
# so "auto" leaves the in-session toggle to you.
DS_THINKING_SLOTS="auto"
DS_THINKING_PRO="on"
DS_THINKING_FLASH="auto"

# Reasoning effort. DeepSeek maps the Anthropic output_config.effort field to
# its own thinking effort (high, and max -> xhigh). budget_tokens is ignored.
DS_EFFORT_LEVEL="high"

# Max output tokens. DeepSeek V4 allows up to 384000; Claude Code defaults are
# much lower. Keep this comfortably below the context window.
DS_MAX_OUTPUT_TOKENS="65536"

# Installation locations. Override on the installer command line if needed:
#   DS_HOME="$HOME/.local/share/ds" DEST_DIR="$HOME/.local/bin" ./install-ds.sh
DS_HOME="${DS_HOME:-$HOME/.ds}"
DEST_DIR="${DEST_DIR:-/usr/local/bin}"

# ---------------------------------------------------------------------------
# Normally no edits are needed below this line.
# ---------------------------------------------------------------------------
set -Eeuo pipefail
umask 077

log()  { printf '[ds-install] %s\n' "$*"; }
warn() { printf '[ds-install] WARNING: %s\n' "$*" >&2; }
fail() { printf '[ds-install] ERROR: %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

write_shell_var() {
  local name="$1" value="$2"
  printf '%s=%q\n' "$name" "$value"
}

# --- Claude Code executable ------------------------------------------------
# The executable is shared with normal `claude`; its profile is not.
export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
if ! command_exists claude; then
  if command_exists npm; then
    log 'Claude Code not found; installing it globally with npm...'
    npm install -g @anthropic-ai/claude-code
  elif command_exists curl; then
    log 'Claude Code not found; installing it with the official native installer...'
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
  else
    fail "Neither npm nor curl is available. Install Claude Code first."
  fi
fi
command_exists claude || fail "'claude' is still not on PATH after installation."
log "Claude Code executable: $(command -v claude)"

# --- Isolated profile root -------------------------------------------------
mkdir -p "$DS_HOME" "$DS_HOME/credentials" "$DS_HOME/runtime" "$DS_HOME/logs"
chmod 700 "$DS_HOME" "$DS_HOME/credentials" "$DS_HOME/runtime" "$DS_HOME/logs"

# Remove a symlink created by an older installer. A regular ~/.ds/CLAUDE.md is
# preserved because it belongs to the isolated ds profile.
if [ -L "$DS_HOME/CLAUDE.md" ]; then
  link_target="$(readlink "$DS_HOME/CLAUDE.md" 2>/dev/null || true)"
  case "$link_target" in
    "$HOME/.claude/CLAUDE.md"|../.claude/CLAUDE.md)
      rm -f "$DS_HOME/CLAUDE.md"
      log 'Removed old shared CLAUDE.md symlink.'
      ;;
  esac
fi

# Keep existing ds preferences, but remove routing/auth/model keys that could
# override the launcher. Never copy ~/.claude/settings.json into this profile.
SETTINGS_FILE="$DS_HOME/settings.json"
[ -e "$SETTINGS_FILE" ] || printf '{}\n' > "$SETTINGS_FILE"

sanitize_settings_with_python() {
  python3 - "$SETTINGS_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = {}
try:
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(loaded, dict):
        data = loaded
except Exception:
    pass

for key in (
    "apiKeyHelper",
    "model",
    "modelOverrides",
    "availableModels",
    "enforceAvailableModels",
):
    data.pop(key, None)

env = data.get("env")
if isinstance(env, dict):
    blocked = {
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_SMALL_FAST_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
        "ANTHROPIC_DEFAULT_FABLE_MODEL",
        "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME",
        "CLAUDE_CODE_SUBAGENT_MODEL",
        "ENABLE_TOOL_SEARCH",
        "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
        "CLAUDE_CODE_EFFORT_LEVEL",
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
    }
    for key in blocked:
        env.pop(key, None)
    if not env:
        data.pop("env", None)

path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
}

sanitize_settings_with_node() {
  node - "$SETTINGS_FILE" <<'JS'
const fs = require('fs');
const path = process.argv[2];
let data = {};
try {
  const loaded = JSON.parse(fs.readFileSync(path, 'utf8'));
  if (loaded && typeof loaded === 'object' && !Array.isArray(loaded)) data = loaded;
} catch (_) {}
for (const key of ['apiKeyHelper', 'model', 'modelOverrides', 'availableModels', 'enforceAvailableModels']) {
  delete data[key];
}
if (data.env && typeof data.env === 'object' && !Array.isArray(data.env)) {
  for (const key of [
    'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_MODEL', 'ANTHROPIC_SMALL_FAST_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
    'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    'ANTHROPIC_DEFAULT_FABLE_MODEL', 'ANTHROPIC_DEFAULT_FABLE_MODEL_NAME',
    'CLAUDE_CODE_SUBAGENT_MODEL', 'ENABLE_TOOL_SEARCH',
    'CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'CLAUDE_CODE_EFFORT_LEVEL',
    'CLAUDE_CODE_MAX_OUTPUT_TOKENS'
  ]) delete data.env[key];
  if (Object.keys(data.env).length === 0) delete data.env;
}
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(path, 0o600);
JS
}

if command_exists python3; then
  sanitize_settings_with_python || fail "Could not sanitize $SETTINGS_FILE"
elif command_exists node; then
  sanitize_settings_with_node || fail "Could not sanitize $SETTINGS_FILE"
else
  warn 'Neither python3 nor node is available; resetting isolated settings.json.'
  cp -p "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)" 2>/dev/null || true
  printf '{}\n' > "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
fi

# --- API key ---------------------------------------------------------------
# Resolution order at launch time (see `ds --check-key`):
#   1. $DEEPSEEK_API_KEY exported in the calling shell
#   2. $DS_HOME/credentials/deepseek_api_key (mode 600)
# The env var always wins, so a shell export can temporarily override the file
# without editing anything.
KEY_FILE="$DS_HOME/credentials/deepseek_api_key"

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  printf '%s\n' "$DEEPSEEK_API_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  log 'Stored $DEEPSEEK_API_KEY in the isolated credentials file.'
elif [ -s "$KEY_FILE" ]; then
  chmod 600 "$KEY_FILE"
  log 'Reusing the existing key in ~/.ds/credentials/deepseek_api_key.'
elif [ -t 0 ]; then
  read -rsp 'DeepSeek API key (press Enter to skip and set it later): ' DEEPSEEK_API_KEY_INPUT
  printf '\n'
  if [ -n "$DEEPSEEK_API_KEY_INPUT" ]; then
    printf '%s\n' "$DEEPSEEK_API_KEY_INPUT" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
  fi
  unset DEEPSEEK_API_KEY_INPUT
fi

# --- Editable model configuration -----------------------------------------
MODELS_FILE="$DS_HOME/models.env"
MODELS_TMP="$MODELS_FILE.tmp.$$"
{
  printf '# Generated by install-ds.sh. You may edit this file directly.\n'
  printf '# Rerunning install-ds.sh replaces it with the values at the top of the installer.\n'
  write_shell_var DEEPSEEK_ANTHROPIC_BASE_URL "$DEEPSEEK_ANTHROPIC_BASE_URL"
  write_shell_var DEEPSEEK_MODELS_URL "$DEEPSEEK_MODELS_URL"
  write_shell_var DEEPSEEK_BALANCE_URL "$DEEPSEEK_BALANCE_URL"
  write_shell_var DS_DEFAULT_PROFILE "$DS_DEFAULT_PROFILE"
  write_shell_var DS_SLOTS_START_ALIAS "$DS_SLOTS_START_ALIAS"
  write_shell_var ANTHROPIC_DEFAULT_OPUS_MODEL "$ANTHROPIC_DEFAULT_OPUS_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_OPUS_MODEL_NAME "$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_SONNET_MODEL "$ANTHROPIC_DEFAULT_SONNET_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_SONNET_MODEL_NAME "$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_HAIKU_MODEL "$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME "$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_FABLE_MODEL "$ANTHROPIC_DEFAULT_FABLE_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_FABLE_MODEL_NAME "$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"
  write_shell_var CLAUDE_CODE_SUBAGENT_MODEL "$CLAUDE_CODE_SUBAGENT_MODEL"
  write_shell_var DS_MODEL_PRO "$DS_MODEL_PRO"
  write_shell_var DS_MODEL_FLASH "$DS_MODEL_FLASH"
  write_shell_var DS_CONTEXT_PRO "$DS_CONTEXT_PRO"
  write_shell_var DS_CONTEXT_FLASH "$DS_CONTEXT_FLASH"
  write_shell_var DS_CONTEXT_SLOTS "$DS_CONTEXT_SLOTS"
  write_shell_var DS_THINKING_SLOTS "$DS_THINKING_SLOTS"
  write_shell_var DS_THINKING_PRO "$DS_THINKING_PRO"
  write_shell_var DS_THINKING_FLASH "$DS_THINKING_FLASH"
  write_shell_var DS_EFFORT_LEVEL "$DS_EFFORT_LEVEL"
  write_shell_var DS_MAX_OUTPUT_TOKENS "$DS_MAX_OUTPUT_TOKENS"
} > "$MODELS_TMP"
chmod 600 "$MODELS_TMP"
mv -f "$MODELS_TMP" "$MODELS_FILE"

# --- Isolated onboarding state --------------------------------------------
ONBOARDING_FILE="$DS_HOME/.claude.json"
if command_exists python3; then
  python3 - "$ONBOARDING_FILE" <<'PY' || true
import json
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = {}
try:
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(loaded, dict):
        data = loaded
except Exception:
    pass
data["hasCompletedOnboarding"] = True
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
elif command_exists node; then
  node - "$ONBOARDING_FILE" <<'JS' || true
const fs = require('fs');
const path = process.argv[2];
let data = {};
try {
  const loaded = JSON.parse(fs.readFileSync(path, 'utf8'));
  if (loaded && typeof loaded === 'object' && !Array.isArray(loaded)) data = loaded;
} catch (_) {}
data.hasCompletedOnboarding = true;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(path, 0o600);
JS
else
  printf '{"hasCompletedOnboarding":true}\n' > "$ONBOARDING_FILE"
  chmod 600 "$ONBOARDING_FILE"
fi

# --- Launcher --------------------------------------------------------------
TMP_WRAPPER="$(mktemp)"
trap 'rm -f "$TMP_WRAPPER" "$MODELS_TMP"' EXIT
{
printf '#!/usr/bin/env bash\n'
# Bake in the profile root chosen at install time; $DS_HOME still overrides it.
write_shell_var DS_HOME_DEFAULT "$DS_HOME"
cat <<'DS_WRAPPER'
# ds — isolated Claude Code launcher for the DeepSeek Anthropic-compatible API.
set -Eeuo pipefail
umask 077

ds_die()  { printf '[ds] ERROR: %s\n' "$*" >&2; exit 1; }
ds_warn() { printf '[ds] WARNING: %s\n' "$*" >&2; }

export CLAUDE_CONFIG_DIR="${DS_HOME:-${DS_HOME_DEFAULT:-$HOME/.ds}}"
DS_HOME="$CLAUDE_CONFIG_DIR"
MODELS_FILE="${DS_MODELS_FILE:-$DS_HOME/models.env}"
KEY_FILE="${DS_KEY_FILE:-$DS_HOME/credentials/deepseek_api_key}"
RUNTIME_DIR="$DS_HOME/runtime"
LOG_DIR="$DS_HOME/logs"

mkdir -p "$DS_HOME" "$RUNTIME_DIR" "$LOG_DIR" "$(dirname "$KEY_FILE")"
chmod 700 "$DS_HOME" "$RUNTIME_DIR" "$LOG_DIR" 2>/dev/null || true

[ -r "$MODELS_FILE" ] || ds_die "Model config not found: $MODELS_FILE. Rerun install-ds.sh."
# This file is generated locally by install-ds.sh and owned by the user.
# shellcheck disable=SC1090
. "$MODELS_FILE"

ds_help() {
  cat <<'HELP'
Usage:
  ds [Claude Code arguments]
  ds --profile PROFILE [Claude Code arguments]
  ds --model-id MODEL --context TOKENS [--thinking on|off|auto] [arguments]

Profiles:
  slots  Mixed aliases: opus=V4 Pro, sonnet/haiku/fable=V4 Flash.
         Switch models in-session with /model opus | /model sonnet.
  pro    Pin all main/background/subagent slots to deepseek-v4-pro.
  flash  Pin all slots to deepseek-v4-flash.

Wrapper options:
  -P, --profile NAME       Select a profile.
      --model-id MODEL     Pin every slot to an arbitrary DeepSeek model ID.
      --context TOKENS     Context window for --model-id.
      --thinking MODE      on, off, or auto (overrides the profile default).
      --profiles           Show configured profile mappings.
      --api-models         Query the DeepSeek List Models API.
      --balance            Query the DeepSeek account balance API.
      --set-key            Store or replace the DeepSeek API key.
      --check-key          Show which key source ds would use (masked).
      --show-config        Print the effective ds configuration, without key.
      --ds-help            Show this help.
      --                   Stop parsing ds options; pass the rest to Claude.

API key resolution (first match wins):
  1. $DEEPSEEK_API_KEY exported in the current shell
  2. ~/.ds/credentials/deepseek_api_key   (created by install-ds.sh or --set-key)

Examples:
  ds
  ds -P pro
  ds -P flash --permission-mode plan
  ds -P pro -p 'review this repository'
  ds --model-id deepseek-v5-pro --context 1048576
  ds -- --help             # pass --help to the Claude Code CLI
HELP
}

ds_profiles() {
  cat <<EOF
Configured ds profiles:
  default : $DS_DEFAULT_PROFILE
  slots   : start=$DS_SLOTS_START_ALIAS, context=$DS_CONTEXT_SLOTS, thinking=$DS_THINKING_SLOTS
            opus   -> $ANTHROPIC_DEFAULT_OPUS_MODEL
            sonnet -> $ANTHROPIC_DEFAULT_SONNET_MODEL
            haiku  -> $ANTHROPIC_DEFAULT_HAIKU_MODEL
            fable  -> $ANTHROPIC_DEFAULT_FABLE_MODEL
            subagent -> $CLAUDE_CODE_SUBAGENT_MODEL
  pro     : $DS_MODEL_PRO  (context=$DS_CONTEXT_PRO, thinking=$DS_THINKING_PRO)
  flash   : $DS_MODEL_FLASH  (context=$DS_CONTEXT_FLASH, thinking=$DS_THINKING_FLASH)
EOF
}

DS_KEY=""
DS_KEY_SOURCE=""

ds_load_key() {
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    DS_KEY="$DEEPSEEK_API_KEY"
    DS_KEY_SOURCE='$DEEPSEEK_API_KEY (environment)'
    return 0
  fi
  if [ -r "$KEY_FILE" ]; then
    IFS= read -r DS_KEY < "$KEY_FILE" || true
    if [ -n "$DS_KEY" ]; then
      DS_KEY_SOURCE="$KEY_FILE"
      return 0
    fi
  fi
  return 1
}

ds_require_key() {
  ds_load_key && return 0
  cat >&2 <<EOF
[ds] ERROR: No DeepSeek API key found.

Fix it with either of these:
  export DEEPSEEK_API_KEY='sk-...'    # add it to ~/.bashrc or ~/.zshrc
  ds --set-key                        # store it in $KEY_FILE (mode 600)

Get a key at https://platform.deepseek.com/api_keys
EOF
  exit 1
}

ds_mask() {
  local key="$1" len=${#1}
  if [ "$len" -le 8 ]; then
    printf '****\n'
  else
    printf '%s...%s (%d chars)\n' "${key:0:5}" "${key: -4}" "$len"
  fi
}

ds_set_key() {
  [ -t 0 ] || ds_die '--set-key requires an interactive terminal.'
  local new_key=""
  read -rsp 'DeepSeek API key: ' new_key
  printf '\n'
  [ -n "$new_key" ] || ds_die 'Empty API key.'
  mkdir -p "$(dirname "$KEY_FILE")"
  chmod 700 "$(dirname "$KEY_FILE")" 2>/dev/null || true
  printf '%s\n' "$new_key" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  printf '[ds] Key stored in %s\n' "$KEY_FILE"
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    ds_warn '$DEEPSEEK_API_KEY is exported in this shell and takes precedence over the file.'
  fi
}

ds_check_key() {
  if ds_load_key; then
    printf 'ds key source : %s\n' "$DS_KEY_SOURCE"
    printf 'ds key value  : %s' ''
    ds_mask "$DS_KEY"
    if [ -n "${DEEPSEEK_API_KEY:-}" ] && [ -s "$KEY_FILE" ]; then
      printf 'note          : a stored key also exists in %s (env wins)\n' "$KEY_FILE"
    fi
  else
    printf 'ds key source : none\n'
    printf 'Set one with:  export DEEPSEEK_API_KEY=... or ds --set-key\n'
  fi
}

ds_api_models() {
  ds_require_key
  command -v curl >/dev/null 2>&1 || ds_die "curl is required for --api-models."
  response="$(curl -fsS "$DEEPSEEK_MODELS_URL" -H "Authorization: Bearer $DS_KEY")" || \
    ds_die 'DeepSeek List Models request failed.'
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$response" | jq -r '.data[] | .id'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(m.get("id")) for m in d.get("data", [])]'
  else
    printf '%s\n' "$response"
  fi
}

ds_balance() {
  ds_require_key
  command -v curl >/dev/null 2>&1 || ds_die "curl is required for --balance."
  response="$(curl -fsS "$DEEPSEEK_BALANCE_URL" -H "Authorization: Bearer $DS_KEY")" || \
    ds_die 'DeepSeek balance request failed.'
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$response" | jq .
  else
    printf '%s\n' "$response"
  fi
}

profile="${DS_PROFILE:-$DS_DEFAULT_PROFILE}"
custom_model=""
custom_context=""
custom_thinking=""
show_config=0
claude_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -P|--profile)
      [ "$#" -ge 2 ] || ds_die "$1 requires a profile name."
      profile="$2"
      shift 2
      ;;
    --profile=*)
      profile="${1#*=}"
      shift
      ;;
    --model-id)
      [ "$#" -ge 2 ] || ds_die "$1 requires a model ID."
      custom_model="$2"
      shift 2
      ;;
    --model-id=*)
      custom_model="${1#*=}"
      shift
      ;;
    --context)
      [ "$#" -ge 2 ] || ds_die "$1 requires a token count."
      custom_context="$2"
      shift 2
      ;;
    --context=*)
      custom_context="${1#*=}"
      shift
      ;;
    --thinking)
      [ "$#" -ge 2 ] || ds_die "$1 requires on, off, or auto."
      custom_thinking="$2"
      shift 2
      ;;
    --thinking=*)
      custom_thinking="${1#*=}"
      shift
      ;;
    --profiles|--list-profiles)
      ds_profiles
      exit 0
      ;;
    --api-models)
      ds_api_models
      exit 0
      ;;
    --balance)
      ds_balance
      exit 0
      ;;
    --set-key)
      ds_set_key
      exit 0
      ;;
    --check-key)
      ds_check_key
      exit 0
      ;;
    --show-config)
      show_config=1
      shift
      ;;
    --ds-help)
      ds_help
      exit 0
      ;;
    --)
      shift
      claude_args+=("$@")
      break
      ;;
    *)
      claude_args+=("$1")
      shift
      ;;
  esac
done

if [ -n "$custom_thinking" ]; then
  case "$custom_thinking" in
    on|off|auto) ;;
    *) ds_die "--thinking must be on, off, or auto." ;;
  esac
fi

if [ -n "$custom_model" ]; then
  [ -n "$custom_context" ] || ds_die '--context is required with --model-id.'
  case "$custom_context" in
    *[!0-9]*|'') ds_die '--context must be a positive integer.' ;;
  esac
  [ "$custom_context" -gt 0 ] || ds_die '--context must be greater than zero.'
  profile="custom"
fi

# Resolve the selected profile into one complete model routing set.
start_alias="opus"
case "$profile" in
  slots)
    model_label="mixed slots"
    compact_window="$DS_CONTEXT_SLOTS"
    start_alias="$DS_SLOTS_START_ALIAS"
    force_thinking="$DS_THINKING_SLOTS"
    opus_model="$ANTHROPIC_DEFAULT_OPUS_MODEL"
    opus_name="$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
    sonnet_model="$ANTHROPIC_DEFAULT_SONNET_MODEL"
    sonnet_name="$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"
    haiku_model="$ANTHROPIC_DEFAULT_HAIKU_MODEL"
    haiku_name="$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"
    fable_model="$ANTHROPIC_DEFAULT_FABLE_MODEL"
    fable_name="$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"
    subagent_model="$CLAUDE_CODE_SUBAGENT_MODEL"
    ;;
  pro)
    selected_model="$DS_MODEL_PRO"
    model_label="$selected_model"
    compact_window="$DS_CONTEXT_PRO"
    force_thinking="$DS_THINKING_PRO"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="DeepSeek V4 Pro pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    ;;
  flash)
    selected_model="$DS_MODEL_FLASH"
    model_label="$selected_model"
    compact_window="$DS_CONTEXT_FLASH"
    force_thinking="$DS_THINKING_FLASH"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="DeepSeek V4 Flash pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    ;;
  custom)
    selected_model="$custom_model"
    model_label="$selected_model"
    compact_window="$custom_context"
    force_thinking="auto"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Custom DeepSeek model"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    ;;
  *)
    ds_die "Unknown profile '$profile'. Run: ds --profiles"
    ;;
esac

# An explicit --thinking flag overrides the profile default.
[ -n "$custom_thinking" ] && force_thinking="$custom_thinking"
case "$force_thinking" in
  on|off|auto) ;;
  *) ds_die "Thinking mode must be on, off, or auto (got '$force_thinking')." ;;
esac

case "$start_alias" in
  opus|sonnet|haiku|fable) ;;
  *) ds_die "DS_SLOTS_START_ALIAS must be opus, sonnet, haiku, or fable." ;;
esac
case "$compact_window" in
  *[!0-9]*|'') ds_die "Invalid context window for profile '$profile': $compact_window" ;;
esac

if [ "$show_config" -eq 1 ]; then
  key_state='missing'
  ds_load_key && key_state="$DS_KEY_SOURCE"
  cat <<EOF
ds effective configuration:
  profile          : $profile
  config directory : $CLAUDE_CONFIG_DIR
  base URL         : $DEEPSEEK_ANTHROPIC_BASE_URL
  start alias      : $start_alias
  active mapping   : $model_label
  opus             : $opus_model
  sonnet           : $sonnet_model
  haiku            : $haiku_model
  fable            : $fable_model
  subagent         : $subagent_model
  compact window   : $compact_window
  thinking         : $force_thinking
  effort level     : ${DS_EFFORT_LEVEL:-high}
  max output       : ${DS_MAX_OUTPUT_TOKENS:-65536}
  key source       : $key_state
EOF
  exit 0
fi

ds_require_key

export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
command -v claude >/dev/null 2>&1 || ds_die "'claude' is not on PATH. Rerun install-ds.sh."

# Clear parent-shell provider/auth routing. The values below affect only this
# ds process and its children; they cannot modify the parent shell.
unset ANTHROPIC_API_KEY
unset ANTHROPIC_MODEL
unset ANTHROPIC_BEDROCK_BASE_URL
unset ANTHROPIC_VERTEX_BASE_URL
unset ANTHROPIC_FOUNDRY_BASE_URL
unset CLAUDE_CODE_USE_BEDROCK
unset CLAUDE_CODE_USE_VERTEX
unset CLAUDE_CODE_USE_FOUNDRY
unset CLAUDE_CODE_USE_ANTHROPIC_AWS

export ANTHROPIC_BASE_URL="$DEEPSEEK_ANTHROPIC_BASE_URL"
export ANTHROPIC_AUTH_TOKEN="$DS_KEY"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model"
export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="$opus_name"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model"
export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="$sonnet_name"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model"
export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="$haiku_name"
export ANTHROPIC_DEFAULT_FABLE_MODEL="$fable_model"
export ANTHROPIC_DEFAULT_FABLE_MODEL_NAME="$fable_name"
# Deprecated, but set for compatibility with older Claude Code releases.
export ANTHROPIC_SMALL_FAST_MODEL="$haiku_model"
export CLAUDE_CODE_SUBAGENT_MODEL="$subagent_model"

export ENABLE_TOOL_SEARCH="false"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$compact_window"
export CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-${DS_EFFORT_LEVEL:-high}}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-${DS_MAX_OUTPUT_TOKENS:-65536}}"
export API_TIMEOUT_MS="${API_TIMEOUT_MS:-600000}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL="1"
export DISABLE_AUTOUPDATER="1"
export DISABLE_TELEMETRY="1"
export DISABLE_LOGIN_COMMAND="1"
export DISABLE_LOGOUT_COMMAND="1"
export CLAUDE_CODE_DEBUG_LOGS_DIR="$LOG_DIR"

# A highest-priority --settings file prevents project/user settings.json env
# blocks from silently replacing the DeepSeek endpoint, key, model aliases, or
# context window. It is kept under ~/.ds and mode 0600.
runtime_key="$(printf '%s\n' "$profile|$compact_window|$opus_model|$sonnet_model|$haiku_model|$fable_model|$subagent_model|$force_thinking" | cksum | awk '{print $1}')"
runtime_file="$RUNTIME_DIR/settings-$profile-$runtime_key.json"
runtime_tmp="$runtime_file.tmp.$$"

export DS_JSON_RUNTIME_FILE="$runtime_tmp"
export DS_JSON_FORCE_THINKING="$force_thinking"

write_runtime_with_python() {
  python3 - <<'PY'
import json
import os
from pathlib import Path

keys = [
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
    "ANTHROPIC_DEFAULT_FABLE_MODEL",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME",
    "ANTHROPIC_SMALL_FAST_MODEL",
    "CLAUDE_CODE_SUBAGENT_MODEL",
    "ENABLE_TOOL_SEARCH",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
    "CLAUDE_CODE_EFFORT_LEVEL",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
    "API_TIMEOUT_MS",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
    "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL",
    "DISABLE_AUTOUPDATER",
    "DISABLE_TELEMETRY",
    "DISABLE_LOGIN_COMMAND",
    "DISABLE_LOGOUT_COMMAND",
    "CLAUDE_CODE_DEBUG_LOGS_DIR",
]
data = {"env": {key: os.environ[key] for key in keys}}
# An empty key at highest settings priority neutralizes conflicting project env.
data["env"]["ANTHROPIC_API_KEY"] = ""
for key in (
    "CLAUDE_CODE_USE_BEDROCK",
    "CLAUDE_CODE_USE_VERTEX",
    "CLAUDE_CODE_USE_FOUNDRY",
    "CLAUDE_CODE_USE_ANTHROPIC_AWS",
):
    data["env"][key] = ""
thinking = os.environ.get("DS_JSON_FORCE_THINKING", "auto")
if thinking == "on":
    data["alwaysThinkingEnabled"] = True
elif thinking == "off":
    data["alwaysThinkingEnabled"] = False
path = Path(os.environ["DS_JSON_RUNTIME_FILE"])
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
}

write_runtime_with_node() {
  node <<'JS'
const fs = require('fs');
const keys = [
  'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN',
  'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
  'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
  'ANTHROPIC_DEFAULT_FABLE_MODEL', 'ANTHROPIC_DEFAULT_FABLE_MODEL_NAME',
  'ANTHROPIC_SMALL_FAST_MODEL', 'CLAUDE_CODE_SUBAGENT_MODEL',
  'ENABLE_TOOL_SEARCH', 'CLAUDE_CODE_AUTO_COMPACT_WINDOW',
  'CLAUDE_CODE_EFFORT_LEVEL', 'CLAUDE_CODE_MAX_OUTPUT_TOKENS',
  'API_TIMEOUT_MS',
  'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
  'CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL',
  'DISABLE_AUTOUPDATER', 'DISABLE_TELEMETRY',
  'DISABLE_LOGIN_COMMAND', 'DISABLE_LOGOUT_COMMAND',
  'CLAUDE_CODE_DEBUG_LOGS_DIR'
];
const env = {};
for (const key of keys) env[key] = process.env[key];
env.ANTHROPIC_API_KEY = '';
for (const key of [
  'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX',
  'CLAUDE_CODE_USE_FOUNDRY', 'CLAUDE_CODE_USE_ANTHROPIC_AWS'
]) env[key] = '';
const data = { env };
if (process.env.DS_JSON_FORCE_THINKING === 'on') data.alwaysThinkingEnabled = true;
if (process.env.DS_JSON_FORCE_THINKING === 'off') data.alwaysThinkingEnabled = false;
fs.writeFileSync(process.env.DS_JSON_RUNTIME_FILE, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(process.env.DS_JSON_RUNTIME_FILE, 0o600);
JS
}

if command -v python3 >/dev/null 2>&1; then
  write_runtime_with_python || ds_die 'Could not write runtime settings with python3.'
elif command -v node >/dev/null 2>&1; then
  write_runtime_with_node || ds_die 'Could not write runtime settings with node.'
else
  ds_die 'python3 or node is required to create the protected runtime settings file.'
fi
mv -f "$runtime_tmp" "$runtime_file"
chmod 600 "$runtime_file"
unset DS_JSON_RUNTIME_FILE DS_JSON_FORCE_THINKING

# Add a startup alias unless the caller already supplied Claude's --model flag.
has_model_arg=0
for arg in ${claude_args[@]+"${claude_args[@]}"}; do
  case "$arg" in
    --model|--model=*) has_model_arg=1; break ;;
  esac
done

launch_args=(--settings "$runtime_file")
if [ "$has_model_arg" -eq 0 ]; then
  launch_args+=(--model "$start_alias")
fi

exec claude "${launch_args[@]}" ${claude_args[@]+"${claude_args[@]}"}
DS_WRAPPER
} > "$TMP_WRAPPER"
chmod 0755 "$TMP_WRAPPER"

mkdir_dest() {
  if [ -d "$DEST_DIR" ]; then
    return 0
  fi
  if mkdir -p "$DEST_DIR" 2>/dev/null; then
    return 0
  fi
  if command_exists sudo; then
    sudo mkdir -p "$DEST_DIR"
  else
    fail "$DEST_DIR does not exist and cannot be created without sudo."
  fi
}
mkdir_dest

if [ -w "$DEST_DIR" ]; then
  install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/ds"
elif command_exists sudo; then
  sudo install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/ds"
else
  fail "$DEST_DIR is not writable and sudo is unavailable."
fi

cat <<MSG

Installed: $DEST_DIR/ds

Isolation:
  Claude config/history/plugins : $DS_HOME
  DeepSeek key                 : $KEY_FILE
  Model map                    : $MODELS_FILE
  Runtime overrides            : $DS_HOME/runtime
  Debug logs                   : $DS_HOME/logs
  Normal Claude profile        : $HOME/.claude and $HOME/.claude.json (not used)
  Kimi km profile              : $HOME/.km (not used)

Default profile: $DS_DEFAULT_PROFILE

Useful commands:
  ds --profiles
  ds --show-config
  ds --check-key
  ds --api-models
  ds --balance
  ds --profile pro
  ds --profile flash

Inside the default slots profile:
  /model opus    -> $ANTHROPIC_DEFAULT_OPUS_MODEL
  /model sonnet  -> $ANTHROPIC_DEFAULT_SONNET_MODEL
  /model haiku   -> $ANTHROPIC_DEFAULT_HAIKU_MODEL
  /model fable   -> $ANTHROPIC_DEFAULT_FABLE_MODEL

Verify routing inside Claude Code with /status.
MSG

# --- Final API key check ---------------------------------------------------
# ds resolves the key as: $DEEPSEEK_API_KEY first, then the stored key file.
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  log 'DEEPSEEK_API_KEY is set in this environment and was also stored for later shells.'
elif [ -s "$KEY_FILE" ]; then
  cat <<MSG

[ds-install] NOTE: DEEPSEEK_API_KEY is not exported in this shell.
             ds will use the stored key at $KEY_FILE instead, so it works as is.
             To override it temporarily:  export DEEPSEEK_API_KEY='sk-...'
MSG
else
  cat <<MSG

[ds-install] WARNING: No DeepSeek API key found. \`ds\` will refuse to start.

  Fix it with either of these:
    export DEEPSEEK_API_KEY='sk-...'     # add to ~/.bashrc or ~/.zshrc, then rerun this installer
    ds --set-key                         # store it in $KEY_FILE (mode 600)

  Get a key at https://platform.deepseek.com/api_keys
  Verify afterwards with: ds --check-key
MSG
fi
