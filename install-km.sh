#!/usr/bin/env bash
# install-km.sh — install an isolated `km` launcher for Claude Code + Kimi.
#
# `km` shares only the Claude Code executable and the current project files.
# Its user configuration, history, plugins, credentials, runtime settings, and
# logs live under KM_HOME (default: ~/.km), not ~/.claude or ~/.claude.json.
#
# ---------------------------------------------------------------------------
# EDIT THIS BLOCK WHEN KIMI RELEASES OR RENAMES MODELS, THEN RERUN THIS SCRIPT.
# ---------------------------------------------------------------------------

# Kimi endpoint and default launcher behavior.
MOONSHOT_ANTHROPIC_BASE_URL="https://api.moonshot.cn/anthropic"
MOONSHOT_MODELS_URL="https://api.moonshot.cn/v1/models"
KM_DEFAULT_PROFILE="slots"       # slots | k3 | code | fast | k26
KM_SLOTS_START_ALIAS="sonnet"   # opus | sonnet | haiku | fable

# Claude Code aliases used by `km --profile slots`.
# These exact variable names are intentionally kept near the top for editing.
ANTHROPIC_DEFAULT_OPUS_MODEL="kimi-k3[1m]"
ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="Kimi K3 (1M)"

ANTHROPIC_DEFAULT_SONNET_MODEL="kimi-k2.7-code"
ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="Kimi K2.7 Code"

ANTHROPIC_DEFAULT_HAIKU_MODEL="kimi-k2.6"
ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="Kimi K2.6"

ANTHROPIC_DEFAULT_FABLE_MODEL="kimi-k2.7-code-highspeed"
ANTHROPIC_DEFAULT_FABLE_MODEL_NAME="Kimi K2.7 Code Highspeed"

CLAUDE_CODE_SUBAGENT_MODEL="kimi-k2.7-code"

# Direct profiles. Each direct profile pins every Claude Code model slot,
# including background tasks and subagents, to one Kimi model.
KM_MODEL_K3="$ANTHROPIC_DEFAULT_OPUS_MODEL"
KM_MODEL_CODE="$ANTHROPIC_DEFAULT_SONNET_MODEL"
KM_MODEL_FAST="$ANTHROPIC_DEFAULT_FABLE_MODEL"
KM_MODEL_K26="$ANTHROPIC_DEFAULT_HAIKU_MODEL"

# Context windows used by Claude Code auto-compaction.
KM_CONTEXT_K3="1048576"
KM_CONTEXT_CODE="262144"
KM_CONTEXT_FAST="262144"
KM_CONTEXT_K26="262144"
# Mixed-slot mode must use the smallest context among all mapped models.
KM_CONTEXT_SLOTS="262144"

# Installation locations. Override on the installer command line if needed:
#   KM_HOME="$HOME/.local/share/km" DEST_DIR="$HOME/.local/bin" ./install-km.sh
KM_HOME="${KM_HOME:-$HOME/.km}"
DEST_DIR="${DEST_DIR:-/usr/local/bin}"

# ---------------------------------------------------------------------------
# Normally no edits are needed below this line.
# ---------------------------------------------------------------------------
set -Eeuo pipefail
umask 077

log()  { printf '[km-install] %s\n' "$*"; }
warn() { printf '[km-install] WARNING: %s\n' "$*" >&2; }
fail() { printf '[km-install] ERROR: %s\n' "$*" >&2; exit 1; }

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
mkdir -p "$KM_HOME" "$KM_HOME/credentials" "$KM_HOME/runtime" "$KM_HOME/logs"
chmod 700 "$KM_HOME" "$KM_HOME/credentials" "$KM_HOME/runtime" "$KM_HOME/logs"

# Remove the symlink created by older versions of this installer. A regular
# ~/.km/CLAUDE.md is preserved because it belongs to the isolated km profile.
if [ -L "$KM_HOME/CLAUDE.md" ]; then
  link_target="$(readlink "$KM_HOME/CLAUDE.md" 2>/dev/null || true)"
  case "$link_target" in
    "$HOME/.claude/CLAUDE.md"|../.claude/CLAUDE.md)
      rm -f "$KM_HOME/CLAUDE.md"
      log 'Removed old shared CLAUDE.md symlink.'
      ;;
  esac
fi

# Keep existing km preferences, but remove routing/auth/model keys that could
# override the launcher. Never copy ~/.claude/settings.json into this profile.
SETTINGS_FILE="$KM_HOME/settings.json"
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
    'CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'CLAUDE_CODE_EFFORT_LEVEL'
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
KEY_FILE="$KM_HOME/credentials/moonshot_api_key"
OLD_ENV_FILE="$KM_HOME/env"

# Migrate the older shell-style key file without sourcing it.
if [ ! -s "$KEY_FILE" ] && [ -f "$OLD_ENV_FILE" ]; then
  migrated_key="$(sed -n 's/^MOONSHOT_API_KEY=//p' "$OLD_ENV_FILE" | head -n 1)"
  if [ -n "$migrated_key" ]; then
    printf '%s\n' "$migrated_key" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    rm -f "$OLD_ENV_FILE"
    log 'Migrated the Moonshot key to ~/.km/credentials/moonshot_api_key.'
  fi
fi

if [ -n "${MOONSHOT_API_KEY:-}" ]; then
  printf '%s\n' "$MOONSHOT_API_KEY" > "$KEY_FILE"
elif [ ! -s "$KEY_FILE" ]; then
  [ -t 0 ] || fail 'MOONSHOT_API_KEY is not set and no terminal is available for prompting.'
  read -rsp 'Moonshot API key: ' MOONSHOT_API_KEY
  printf '\n'
  [ -n "$MOONSHOT_API_KEY" ] || fail 'Empty API key.'
  printf '%s\n' "$MOONSHOT_API_KEY" > "$KEY_FILE"
fi
chmod 600 "$KEY_FILE"

# --- Editable model configuration -----------------------------------------
MODELS_FILE="$KM_HOME/models.env"
MODELS_TMP="$MODELS_FILE.tmp.$$"
{
  printf '# Generated by install-km.sh. You may edit this file directly.\n'
  printf '# Rerunning install-km.sh replaces it with the values at the top of the installer.\n'
  write_shell_var MOONSHOT_ANTHROPIC_BASE_URL "$MOONSHOT_ANTHROPIC_BASE_URL"
  write_shell_var MOONSHOT_MODELS_URL "$MOONSHOT_MODELS_URL"
  write_shell_var KM_DEFAULT_PROFILE "$KM_DEFAULT_PROFILE"
  write_shell_var KM_SLOTS_START_ALIAS "$KM_SLOTS_START_ALIAS"
  write_shell_var ANTHROPIC_DEFAULT_OPUS_MODEL "$ANTHROPIC_DEFAULT_OPUS_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_OPUS_MODEL_NAME "$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_SONNET_MODEL "$ANTHROPIC_DEFAULT_SONNET_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_SONNET_MODEL_NAME "$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_HAIKU_MODEL "$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME "$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"
  write_shell_var ANTHROPIC_DEFAULT_FABLE_MODEL "$ANTHROPIC_DEFAULT_FABLE_MODEL"
  write_shell_var ANTHROPIC_DEFAULT_FABLE_MODEL_NAME "$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"
  write_shell_var CLAUDE_CODE_SUBAGENT_MODEL "$CLAUDE_CODE_SUBAGENT_MODEL"
  write_shell_var KM_MODEL_K3 "$KM_MODEL_K3"
  write_shell_var KM_MODEL_CODE "$KM_MODEL_CODE"
  write_shell_var KM_MODEL_FAST "$KM_MODEL_FAST"
  write_shell_var KM_MODEL_K26 "$KM_MODEL_K26"
  write_shell_var KM_CONTEXT_K3 "$KM_CONTEXT_K3"
  write_shell_var KM_CONTEXT_CODE "$KM_CONTEXT_CODE"
  write_shell_var KM_CONTEXT_FAST "$KM_CONTEXT_FAST"
  write_shell_var KM_CONTEXT_K26 "$KM_CONTEXT_K26"
  write_shell_var KM_CONTEXT_SLOTS "$KM_CONTEXT_SLOTS"
} > "$MODELS_TMP"
chmod 600 "$MODELS_TMP"
mv -f "$MODELS_TMP" "$MODELS_FILE"

# --- Isolated onboarding state --------------------------------------------
ONBOARDING_FILE="$KM_HOME/.claude.json"
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
cat > "$TMP_WRAPPER" <<'KM_WRAPPER'
#!/usr/bin/env bash
# km — isolated Claude Code launcher for the Kimi Anthropic-compatible API.
set -Eeuo pipefail
umask 077

km_die()  { printf '[km] ERROR: %s\n' "$*" >&2; exit 1; }
km_warn() { printf '[km] WARNING: %s\n' "$*" >&2; }

export CLAUDE_CONFIG_DIR="${KM_HOME:-$HOME/.km}"
KM_HOME="$CLAUDE_CONFIG_DIR"
MODELS_FILE="${KM_MODELS_FILE:-$KM_HOME/models.env}"
KEY_FILE="${KM_KEY_FILE:-$KM_HOME/credentials/moonshot_api_key}"
RUNTIME_DIR="$KM_HOME/runtime"
LOG_DIR="$KM_HOME/logs"

mkdir -p "$KM_HOME" "$RUNTIME_DIR" "$LOG_DIR"
chmod 700 "$KM_HOME" "$RUNTIME_DIR" "$LOG_DIR" 2>/dev/null || true

[ -r "$MODELS_FILE" ] || km_die "Model config not found: $MODELS_FILE. Rerun install-km.sh."
# This file is generated locally by install-km.sh and owned by the user.
# shellcheck disable=SC1090
. "$MODELS_FILE"

km_help() {
  cat <<'HELP'
Usage:
  km [Claude Code arguments]
  km --profile PROFILE [Claude Code arguments]
  km --model-id MODEL --context TOKENS [--thinking on|off|auto] [arguments]

Profiles:
  slots  Mixed aliases: opus=K3, sonnet=K2.7 Code,
         haiku=K2.6, fable=K2.7 Code Highspeed.
         Uses the smallest configured context window (normally 256K).
  k3     Pin all main/background/subagent slots to Kimi K3 (1M).
  code   Pin all slots to Kimi K2.7 Code (256K; Thinking forced on).
  fast   Pin all slots to Kimi K2.7 Code Highspeed (256K; Thinking on).
  k26    Pin all slots to Kimi K2.6 (256K; Thinking optional).

Wrapper options:
  -P, --profile NAME       Select a profile.
      --model-id MODEL     Pin every slot to an arbitrary Kimi model ID.
      --context TOKENS     Context window for --model-id.
      --thinking MODE      on, off, or auto for --model-id.
      --profiles           Show configured profile mappings.
      --api-models         Query the Moonshot List Models API.
      --show-config        Print the effective km configuration, without key.
      --km-help            Show this help.
      --                   Stop parsing km options; pass the rest to Claude.

Examples:
  km
  km -P k3
  km -P code --permission-mode plan
  km -P fast -p 'review this repository'
  km --model-id 'kimi-k4[1m]' --context 1048576
  km -- --help             # pass --help to the Claude Code CLI
HELP
}

km_profiles() {
  cat <<EOF
Configured km profiles:
  default : $KM_DEFAULT_PROFILE
  slots   : start=$KM_SLOTS_START_ALIAS, context=$KM_CONTEXT_SLOTS
            opus   -> $ANTHROPIC_DEFAULT_OPUS_MODEL
            sonnet -> $ANTHROPIC_DEFAULT_SONNET_MODEL
            haiku  -> $ANTHROPIC_DEFAULT_HAIKU_MODEL
            fable  -> $ANTHROPIC_DEFAULT_FABLE_MODEL
            subagent -> $CLAUDE_CODE_SUBAGENT_MODEL
  k3      : $KM_MODEL_K3  (context=$KM_CONTEXT_K3)
  code    : $KM_MODEL_CODE  (context=$KM_CONTEXT_CODE)
  fast    : $KM_MODEL_FAST  (context=$KM_CONTEXT_FAST)
  k26     : $KM_MODEL_K26  (context=$KM_CONTEXT_K26)
EOF
}

km_read_key() {
  [ -r "$KEY_FILE" ] || km_die "Moonshot key not found: $KEY_FILE. Rerun install-km.sh."
  IFS= read -r MOONSHOT_API_KEY < "$KEY_FILE" || true
  [ -n "${MOONSHOT_API_KEY:-}" ] || km_die "Moonshot key file is empty: $KEY_FILE"
  export MOONSHOT_API_KEY
}

km_api_models() {
  km_read_key
  command -v curl >/dev/null 2>&1 || km_die "curl is required for --api-models."
  response="$(curl -fsS "$MOONSHOT_MODELS_URL" -H "Authorization: Bearer $MOONSHOT_API_KEY")" || \
    km_die 'Moonshot List Models request failed.'
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$response" | jq -r '.data[] | "\(.id)\tcontext=\(.context_length // "unknown")\treasoning=\(.supports_reasoning // "unknown")"'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print("{}\tcontext={}\treasoning={}".format(m.get("id"), m.get("context_length", "unknown"), m.get("supports_reasoning", "unknown"))) for m in d.get("data", [])]'
  else
    printf '%s\n' "$response"
  fi
}

profile="${KM_PROFILE:-$KM_DEFAULT_PROFILE}"
custom_model=""
custom_context=""
custom_thinking="auto"
show_config=0
claude_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -P|--profile)
      [ "$#" -ge 2 ] || km_die "$1 requires a profile name."
      profile="$2"
      shift 2
      ;;
    --profile=*)
      profile="${1#*=}"
      shift
      ;;
    --model-id)
      [ "$#" -ge 2 ] || km_die "$1 requires a model ID."
      custom_model="$2"
      shift 2
      ;;
    --model-id=*)
      custom_model="${1#*=}"
      shift
      ;;
    --context)
      [ "$#" -ge 2 ] || km_die "$1 requires a token count."
      custom_context="$2"
      shift 2
      ;;
    --context=*)
      custom_context="${1#*=}"
      shift
      ;;
    --thinking)
      [ "$#" -ge 2 ] || km_die "$1 requires on, off, or auto."
      custom_thinking="$2"
      shift 2
      ;;
    --thinking=*)
      custom_thinking="${1#*=}"
      shift
      ;;
    --profiles|--list-profiles)
      km_profiles
      exit 0
      ;;
    --api-models)
      km_api_models
      exit 0
      ;;
    --show-config)
      show_config=1
      shift
      ;;
    --km-help)
      km_help
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

case "$custom_thinking" in
  on|off|auto) ;;
  *) km_die "--thinking must be on, off, or auto." ;;
esac

if [ -n "$custom_model" ]; then
  [ -n "$custom_context" ] || km_die '--context is required with --model-id.'
  case "$custom_context" in
    *[!0-9]*|'') km_die '--context must be a positive integer.' ;;
  esac
  [ "$custom_context" -gt 0 ] || km_die '--context must be greater than zero.'
  profile="custom"
fi

# Resolve the selected profile into one complete model routing set.
force_thinking="auto"
start_alias="opus"
case "$profile" in
  slots)
    model_label="mixed slots"
    compact_window="$KM_CONTEXT_SLOTS"
    start_alias="$KM_SLOTS_START_ALIAS"
    opus_model="$ANTHROPIC_DEFAULT_OPUS_MODEL"
    opus_name="$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
    sonnet_model="$ANTHROPIC_DEFAULT_SONNET_MODEL"
    sonnet_name="$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"
    haiku_model="$ANTHROPIC_DEFAULT_HAIKU_MODEL"
    haiku_name="$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"
    fable_model="$ANTHROPIC_DEFAULT_FABLE_MODEL"
    fable_name="$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"
    subagent_model="$CLAUDE_CODE_SUBAGENT_MODEL"
    # K2.7 Code and Highspeed reject requests with thinking disabled.
    force_thinking="on"
    ;;
  k3)
    selected_model="$KM_MODEL_K3"
    model_label="$selected_model"
    compact_window="$KM_CONTEXT_K3"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Kimi K3 pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    ;;
  code)
    selected_model="$KM_MODEL_CODE"
    model_label="$selected_model"
    compact_window="$KM_CONTEXT_CODE"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Kimi K2.7 Code pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    force_thinking="on"
    ;;
  fast)
    selected_model="$KM_MODEL_FAST"
    model_label="$selected_model"
    compact_window="$KM_CONTEXT_FAST"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Kimi K2.7 Code Highspeed pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    force_thinking="on"
    ;;
  k26)
    selected_model="$KM_MODEL_K26"
    model_label="$selected_model"
    compact_window="$KM_CONTEXT_K26"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Kimi K2.6 pinned"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    ;;
  custom)
    selected_model="$custom_model"
    model_label="$selected_model"
    compact_window="$custom_context"
    opus_model="$selected_model"; sonnet_model="$selected_model"
    haiku_model="$selected_model"; fable_model="$selected_model"
    subagent_model="$selected_model"
    opus_name="Custom Kimi model"; sonnet_name="$opus_name"
    haiku_name="$opus_name"; fable_name="$opus_name"
    force_thinking="$custom_thinking"
    ;;
  *)
    km_die "Unknown profile '$profile'. Run: km --profiles"
    ;;
esac

case "$start_alias" in
  opus|sonnet|haiku|fable) ;;
  *) km_die "KM_SLOTS_START_ALIAS must be opus, sonnet, haiku, or fable." ;;
esac
case "$compact_window" in
  *[!0-9]*|'') km_die "Invalid context window for profile '$profile': $compact_window" ;;
esac

if [ "$show_config" -eq 1 ]; then
  cat <<EOF
km effective configuration:
  profile          : $profile
  config directory : $CLAUDE_CONFIG_DIR
  base URL         : $MOONSHOT_ANTHROPIC_BASE_URL
  start alias      : $start_alias
  active mapping   : $model_label
  opus             : $opus_model
  sonnet           : $sonnet_model
  haiku            : $haiku_model
  fable            : $fable_model
  subagent         : $subagent_model
  compact window   : $compact_window
  thinking         : $force_thinking
EOF
  exit 0
fi

km_read_key

export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
command -v claude >/dev/null 2>&1 || km_die "'claude' is not on PATH. Rerun install-km.sh."

# Clear parent-shell provider/auth routing. The values below affect only this
# km process and its children; they cannot modify the parent shell.
unset ANTHROPIC_API_KEY
unset ANTHROPIC_MODEL
unset ANTHROPIC_BEDROCK_BASE_URL
unset ANTHROPIC_VERTEX_BASE_URL
unset ANTHROPIC_FOUNDRY_BASE_URL
unset CLAUDE_CODE_USE_BEDROCK
unset CLAUDE_CODE_USE_VERTEX
unset CLAUDE_CODE_USE_FOUNDRY
unset CLAUDE_CODE_USE_ANTHROPIC_AWS

export ANTHROPIC_BASE_URL="$MOONSHOT_ANTHROPIC_BASE_URL"
export ANTHROPIC_AUTH_TOKEN="$MOONSHOT_API_KEY"
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
export CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-max}"
export API_TIMEOUT_MS="${API_TIMEOUT_MS:-600000}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL="1"
export DISABLE_AUTOUPDATER="1"
export DISABLE_TELEMETRY="1"
export DISABLE_LOGIN_COMMAND="1"
export DISABLE_LOGOUT_COMMAND="1"
export CLAUDE_CODE_DEBUG_LOGS_DIR="$LOG_DIR"

# A highest-priority --settings file prevents project/user settings.json env
# blocks from silently replacing the Kimi endpoint, key, model aliases, or
# context window. It is kept under ~/.km and mode 0600.
runtime_key="$(printf '%s\n' "$profile|$compact_window|$opus_model|$sonnet_model|$haiku_model|$fable_model|$subagent_model" | cksum | awk '{print $1}')"
runtime_file="$RUNTIME_DIR/settings-$profile-$runtime_key.json"
runtime_tmp="$runtime_file.tmp.$$"

export KM_JSON_RUNTIME_FILE="$runtime_tmp"
export KM_JSON_FORCE_THINKING="$force_thinking"

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
thinking = os.environ.get("KM_JSON_FORCE_THINKING", "auto")
if thinking == "on":
    data["alwaysThinkingEnabled"] = True
elif thinking == "off":
    data["alwaysThinkingEnabled"] = False
path = Path(os.environ["KM_JSON_RUNTIME_FILE"])
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
  'CLAUDE_CODE_EFFORT_LEVEL', 'API_TIMEOUT_MS',
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
if (process.env.KM_JSON_FORCE_THINKING === 'on') data.alwaysThinkingEnabled = true;
if (process.env.KM_JSON_FORCE_THINKING === 'off') data.alwaysThinkingEnabled = false;
fs.writeFileSync(process.env.KM_JSON_RUNTIME_FILE, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(process.env.KM_JSON_RUNTIME_FILE, 0o600);
JS
}

if command -v python3 >/dev/null 2>&1; then
  write_runtime_with_python || km_die 'Could not write runtime settings with python3.'
elif command -v node >/dev/null 2>&1; then
  write_runtime_with_node || km_die 'Could not write runtime settings with node.'
else
  km_die 'python3 or node is required to create the protected runtime settings file.'
fi
mv -f "$runtime_tmp" "$runtime_file"
chmod 600 "$runtime_file"
unset KM_JSON_RUNTIME_FILE KM_JSON_FORCE_THINKING

# Add a startup alias unless the caller already supplied Claude's --model flag.
has_model_arg=0
for arg in "${claude_args[@]}"; do
  case "$arg" in
    --model|--model=*) has_model_arg=1; break ;;
  esac
done

launch_args=(--settings "$runtime_file")
if [ "$has_model_arg" -eq 0 ]; then
  launch_args+=(--model "$start_alias")
fi

exec claude "${launch_args[@]}" "${claude_args[@]}"
KM_WRAPPER
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
  install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/km"
elif command_exists sudo; then
  sudo install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/km"
else
  fail "$DEST_DIR is not writable and sudo is unavailable."
fi

cat <<MSG

Installed: $DEST_DIR/km

Isolation:
  Claude config/history/plugins : $KM_HOME
  Moonshot key                 : $KEY_FILE
  Model map                    : $MODELS_FILE
  Runtime overrides            : $KM_HOME/runtime
  Debug logs                   : $KM_HOME/logs
  Normal Claude profile        : $HOME/.claude and $HOME/.claude.json (not used)

Default profile: $KM_DEFAULT_PROFILE

Useful commands:
  km --profiles
  km --show-config
  km --api-models
  km --profile k3
  km --profile code
  km --profile fast
  km --profile k26

Inside the default slots profile:
  /model opus    -> $ANTHROPIC_DEFAULT_OPUS_MODEL
  /model sonnet  -> $ANTHROPIC_DEFAULT_SONNET_MODEL
  /model haiku   -> $ANTHROPIC_DEFAULT_HAIKU_MODEL
  /model fable   -> $ANTHROPIC_DEFAULT_FABLE_MODEL

Verify routing inside Claude Code with /status.
MSG
