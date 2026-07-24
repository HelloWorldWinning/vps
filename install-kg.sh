#!/usr/bin/env bash
# install-kg.sh — installs /usr/local/bin/kg
#   Codex CLI (latest) -> LiteLLM (bundled, loopback) -> Moonshot Chat Completions
#
# Why the proxy: Codex >= 0.84.0 removed wire_api = "chat" and speaks only the
# Responses API. Moonshot serves /v1/chat/completions and returns 404 on
# /v1/responses. LiteLLM translates both directions. It is installed into a
# private venv under $KG_HOME and started/reaped by the kg wrapper, so there is
# no separate service to manage.
#
# CRITICAL: the model id in litellm.yaml must carry the
#   openai/chat_completions/<name>
# prefix. Without it LiteLLM assumes the upstream also speaks Responses and
# proxies /v1/responses straight through -> 404 from Moonshot, which then
# cools the deployment down and surfaces as a misleading 429. The prefix is
# the documented opt-in for the chat-completions bridge (equivalent to
# passing use_chat_completions_api=true).
#
#   default model : kimi-k2.6      (256K context)
#   strongest     : kimi-k3        (1M context)
#   config root   : ~/.kg          (CODEX_HOME — never touches ~/.codex)
set -Eeuo pipefail

# ── Models ───────────────────────────────────────────────────────────────
KIMI_MODELS=(
  "kimi-k3"
  "kimi-k2.7-code"
  "kimi-k2.7-code-highspeed"
  "kimi-k2.6"
)
KIMI_CTX=(
  1048576
  262144
  262144
  262144
)
KIMI_DESC=(
  "Flagship · 1M context · native vision · thinking-only"
  "Coding specialist · reliable long-context instruction following · 256K"
  "Coding · ~180 tok/s output · 256K"
  "General agent · vision + text · thinking modes · 256K"
)

DEFAULT_MODEL="kimi-k2.6"
DEFAULT_CTX="262144"
TOP_MODEL="kimi-k3"
TOP_CTX="1048576"

UPSTREAM_BASE_URL="${MOONSHOT_BASE_URL:-https://api.moonshot.cn/v1}"
KG_PORT="${KG_PORT:-8317}"
PROXY_BASE_URL="http://127.0.0.1:${KG_PORT}/v1"

KG_HOME="${KG_HOME:-$HOME/.kg}"
DEST_DIR="${DEST_DIR:-/usr/local/bin}"
CATALOG="$KG_HOME/kimi-catalog.json"
VENV="$KG_HOME/venv"
LITELLM_YAML="$KG_HOME/litellm.yaml"

log() { printf '[kg-install] %s\n' "$*"; }
fail() {
  printf '[kg-install] ERROR: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$KG_HOME"
chmod 700 "$KG_HOME"

backup() {
  [ -f "$1" ] && cp -p "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && log "Backed up $(basename "$1")"
  return 0
}

# ── codex binary ─────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
if ! command -v codex >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    log "Installing Codex CLI via npm..."
    npm install -g @openai/codex
  elif command -v brew >/dev/null 2>&1; then
    log "Installing Codex CLI via Homebrew..."
    brew install codex
  else
    fail "Neither npm nor brew available; install Codex CLI manually first."
  fi
  export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
fi
command -v codex >/dev/null 2>&1 || fail "'codex' still not on PATH after install."
log "Codex CLI found: $(command -v codex)  ($(codex --version 2>/dev/null || echo 'version unknown'))"

# ── LiteLLM in a private venv ────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || fail "python3 is required to install LiteLLM."

if [ ! -x "$VENV/bin/litellm" ]; then
  log "Creating venv at $VENV ..."
  python3 -m venv "$VENV" 2>/dev/null || {
    fail "python3 -m venv failed. On Debian/Ubuntu: apt install python3-venv"
  }
  log "Installing litellm[proxy] (this pulls ~200MB, be patient)..."
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet 'litellm[proxy]' || fail "pip install litellm[proxy] failed."
fi
"$VENV/bin/litellm" --version >/dev/null 2>&1 ||
  log "WARNING: '$VENV/bin/litellm --version' did not succeed; proxy may not start."
log "LiteLLM ready: $VENV/bin/litellm"

# ── key file (created if absent; never prompts) ──────────────────────────
if [ ! -e "$KG_HOME/env" ]; then
  if [ -n "${MOONSHOT_API_KEY:-}" ]; then
    printf 'MOONSHOT_API_KEY=%s\n' "$MOONSHOT_API_KEY" >"$KG_HOME/env"
    log "Seeded $KG_HOME/env from the current shell environment."
  else
    printf '# MOONSHOT_API_KEY=sk-xxxx\n' >"$KG_HOME/env"
    log "Wrote placeholder $KG_HOME/env — fill in your key before running kg."
  fi
fi
chmod 600 "$KG_HOME/env"

# ── validate the key against the upstream (warn only) ────────────────────
_probe_key="${MOONSHOT_API_KEY:-}"
if [ -z "$_probe_key" ]; then
  _probe_key="$(sed -n 's/^[[:space:]]*MOONSHOT_API_KEY=//p' "$KG_HOME/env" | head -n1)"
fi
if [ -n "$_probe_key" ] && command -v curl >/dev/null 2>&1; then
  _code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
    "$UPSTREAM_BASE_URL/models" -H "Authorization: Bearer $_probe_key" || echo "000")"
  case "$_code" in
    200) log "Upstream key check: OK ($UPSTREAM_BASE_URL)" ;;
    401) log "WARNING: upstream rejected the key (401). Update $KG_HOME/env." ;;
    000) log "WARNING: could not reach $UPSTREAM_BASE_URL (network/DNS?)." ;;
    *)   log "WARNING: upstream returned HTTP $_code on /models." ;;
  esac
fi
unset _probe_key _code

# ── LiteLLM config ───────────────────────────────────────────────────────
# model: openai/<name> + api_base tells LiteLLM to speak Chat Completions
# upstream. Codex hits /v1/responses on the proxy; LiteLLM bridges.
backup "$LITELLM_YAML"
{
  printf 'model_list:\n'
  for ((i = 0; i < ${#KIMI_MODELS[@]}; i++)); do
    printf '  - model_name: %s\n' "${KIMI_MODELS[$i]}"
    printf '    litellm_params:\n'
    printf '      model: openai/chat_completions/%s\n' "${KIMI_MODELS[$i]}"
    printf '      api_base: %s\n' "$UPSTREAM_BASE_URL"
    printf '      api_key: os.environ/MOONSHOT_API_KEY\n'
    printf '    model_info:\n'
    printf '      max_input_tokens: %s\n' "${KIMI_CTX[$i]}"
  done
  cat <<'YAML'

litellm_settings:
  drop_params: true
  telemetry: false
  num_retries: 0

router_settings:
  cooldown_time: 0
  allowed_fails: 1000

general_settings:
  disable_spend_logs: true
YAML
} >"$LITELLM_YAML"
chmod 600 "$LITELLM_YAML"
log "Wrote $LITELLM_YAML"

# ── model catalog for the /model picker ─────────────────────────────────
PAIRS=${#KIMI_MODELS[@]}
backup "$CATALOG"
{
  printf '{\n  "models": [\n'
  for ((i = 0; i < PAIRS; i++)); do
    km="${KIMI_MODELS[$i]}"
    ctx="${KIMI_CTX[$i]}"
    desc="${KIMI_DESC[$i]}"
    priority="$((i + 1))"
    printf '    {\n'
    printf '      "slug": "%s",\n' "$km"
    printf '      "display_name": "%s",\n' "$km"
    printf '      "description": "%s",\n' "$desc"
    printf '      "default_reasoning_level": "high",\n'
    printf '      "supported_reasoning_levels": [\n'
    printf '        {"effort": "low", "description": "Fast responses with lighter reasoning"},\n'
    printf '        {"effort": "medium", "description": "Balances speed and reasoning depth"},\n'
    printf '        {"effort": "high", "description": "Greater reasoning depth for complex tasks"}\n'
    printf '      ],\n'
    printf '      "shell_type": "shell_command",\n'
    printf '      "visibility": "list",\n'
    printf '      "minimal_client_version": "0.0.1",\n'
    printf '      "supported_in_api": true,\n'
    printf '      "availability_nux": null,\n'
    printf '      "upgrade": null,\n'
    printf '      "priority": %s,\n' "$priority"
    printf '      "base_instructions": "You are a coding agent running in the Codex CLI. Work directly in the user workspace. Be precise, concise, and practical. Inspect relevant files before editing them, preserve existing behavior unless the user requests otherwise, and verify changes when possible.",\n'
    printf '      "supports_reasoning_summaries": true,\n'
    printf '      "support_verbosity": false,\n'
    printf '      "default_verbosity": null,\n'
    printf '      "apply_patch_tool_type": "freeform",\n'
    printf '      "web_search_tool_type": "text",\n'
    printf '      "input_modalities": ["text"],\n'
    printf '      "supports_image_detail_original": false,\n'
    printf '      "supports_parallel_tool_calls": true,\n'
    printf '      "truncation_policy": {"mode": "tokens", "limit": 10000},\n'
    printf '      "context_window": %s,\n' "$ctx"
    printf '      "max_context_window": %s,\n' "$ctx"
    printf '      "auto_compact_token_limit": null,\n'
    printf '      "effective_context_window_percent": 95,\n'
    printf '      "reasoning_summary_format": "none",\n'
    printf '      "default_reasoning_summary": "auto",\n'
    printf '      "experimental_supported_tools": []\n'
    if [ "$((i + 1))" -lt "$PAIRS" ]; then printf '    },\n'; else printf '    }\n'; fi
  done
  printf '  ]\n}\n'
} >"$CATALOG"
chmod 600 "$CATALOG"

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CATALOG" &&
  log "Catalog JSON is valid: $CATALOG"

# ── base config.toml ─────────────────────────────────────────────────────
backup "$KG_HOME/config.toml"
cat >"$KG_HOME/config.toml" <<EOF
# Managed by install-kg.sh — isolated Codex profile for Kimi via LiteLLM.
model = "$DEFAULT_MODEL"
model_provider = "kimi"
model_context_window = $DEFAULT_CTX
model_reasoning_effort = "high"
model_reasoning_summary = "auto"
model_supports_reasoning_summaries = true

# The /model picker renders this catalog instead of the built-in gpt-5.x list.
model_catalog_json = "$CATALOG"

# base_url points at the bundled LiteLLM proxy on loopback, NOT at Moonshot.
# Moonshot does not serve /v1/responses; LiteLLM translates to /v1/chat/completions.
[model_providers.kimi]
name = "Kimi (Moonshot via LiteLLM)"
base_url = "$PROXY_BASE_URL"
env_key = "KG_PROXY_KEY"
wire_api = "responses"
request_max_retries = 2
stream_max_retries = 3
stream_idle_timeout_ms = 600000

# Don't leak credentials into subprocesses Codex spawns.
[shell_environment_policy]
exclude = ["MOONSHOT_API_KEY", "KG_PROXY_KEY"]

[otel]
environment = "kg"

[analytics]
enabled = false

[history]
persistence = "save-all"
EOF
chmod 600 "$KG_HOME/config.toml"

# ── profile overlays ─────────────────────────────────────────────────────
write_profile() { # name model ctx
  backup "$KG_HOME/$1.config.toml"
  cat >"$KG_HOME/$1.config.toml" <<EOF
# Profile: $1
model = "$2"
model_provider = "kimi"
model_context_window = $3
model_reasoning_effort = "high"
model_catalog_json = "$CATALOG"
EOF
  chmod 600 "$KG_HOME/$1.config.toml"
}
write_profile k26 "$DEFAULT_MODEL" "$DEFAULT_CTX"
write_profile k3 "$TOP_MODEL" "$TOP_CTX"
write_profile k27code "kimi-k2.7-code" 262144

# Share the user-level AGENTS.md via symlink, if present.
if [ ! -e "$KG_HOME/AGENTS.md" ] && [ -f "$HOME/.codex/AGENTS.md" ]; then
  ln -s "$HOME/.codex/AGENTS.md" "$KG_HOME/AGENTS.md"
fi

# ── launcher ─────────────────────────────────────────────────────────────
TMP_WRAPPER="$(mktemp)"
cat >"$TMP_WRAPPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

KG_PORT="\${KG_PORT:-$KG_PORT}"
EOF
cat >>"$TMP_WRAPPER" <<'EOF'

# --- isolated profile (never touches ~/.codex) ---------------------------
export CODEX_HOME="${KG_HOME:-$HOME/.kg}"
mkdir -p "$CODEX_HOME"
chmod 700 "$CODEX_HOME" 2>/dev/null || true

export XDG_CACHE_HOME="$CODEX_HOME/cache"
export XDG_STATE_HOME="$CODEX_HOME/state"
export XDG_DATA_HOME="$CODEX_HOME/data"
export XDG_CONFIG_HOME="$CODEX_HOME/xdg-config"
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

[ -f "$CODEX_HOME/env" ] && . "$CODEX_HOME/env"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
command -v codex >/dev/null 2>&1 || { echo "'codex' not on PATH" >&2; exit 127; }

# --- credentials: clear foreign ones, keep only Moonshot -----------------
unset OPENAI_API_KEY
unset OPENAI_BASE_URL
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL

if [ -z "${MOONSHOT_API_KEY:-}" ]; then
  cat >&2 <<'WARN'
[kg] MOONSHOT_API_KEY is not set.

  Add it to the isolated key file:
    printf 'MOONSHOT_API_KEY=sk-xxxx\n' > ~/.kg/env && chmod 600 ~/.kg/env

  Key: https://platform.moonshot.cn/console/api-keys
WARN
  exit 1
fi
export MOONSHOT_API_KEY

# Dummy bearer for the loopback proxy. Codex requires env_key to be non-empty;
# LiteLLM has no master_key configured, so the value is not checked.
export KG_PROXY_KEY="sk-kg-local"

VENV="$CODEX_HOME/venv"
LITELLM_YAML="$CODEX_HOME/litellm.yaml"
LOG="$XDG_STATE_HOME/litellm.log"
PROXY_PID=""

proxy_up() {
  curl -sf -m 2 "http://127.0.0.1:$KG_PORT/health/liveliness" >/dev/null 2>&1 ||
  curl -sf -m 2 "http://127.0.0.1:$KG_PORT/v1/models" \
       -H "Authorization: Bearer $KG_PROXY_KEY" >/dev/null 2>&1
}

cleanup() {
  if [ -n "$PROXY_PID" ]; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
}

if proxy_up; then
  echo "[kg] reusing LiteLLM already listening on 127.0.0.1:$KG_PORT" >&2
else
  [ -x "$VENV/bin/litellm" ] || {
    echo "[kg] LiteLLM missing at $VENV/bin/litellm — re-run install-kg.sh" >&2
    exit 127
  }
  : >"$LOG"
  "$VENV/bin/litellm" --config "$LITELLM_YAML" \
      --host 127.0.0.1 --port "$KG_PORT" >>"$LOG" 2>&1 &
  PROXY_PID=$!
  trap cleanup EXIT INT TERM

  printf '[kg] starting LiteLLM on 127.0.0.1:%s ' "$KG_PORT" >&2
  ready=0
  for _ in $(seq 120); do
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
      echo "" >&2
      echo "[kg] LiteLLM exited during startup. Last lines of $LOG:" >&2
      tail -n 30 "$LOG" >&2
      exit 1
    fi
    if proxy_up; then ready=1; break; fi
    printf '.' >&2
    sleep 0.5
  done
  echo "" >&2
  if [ "$ready" -ne 1 ]; then
    echo "[kg] LiteLLM did not become ready in 60s. Last lines of $LOG:" >&2
    tail -n 30 "$LOG" >&2
    exit 1
  fi
  echo "[kg] proxy ready (log: $LOG)" >&2
fi

# Respect a caller-supplied --profile / -p / --model / -m.
case " $* " in
  *" --profile "*|*" -p "*|*" --model "*|*" -m "*) codex "$@" ;;
  *)                                               codex --profile k26 "$@" ;;
esac
EOF
chmod 0755 "$TMP_WRAPPER"

if [ -w "$DEST_DIR" ]; then
  install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/kg"
elif command -v sudo >/dev/null 2>&1; then
  sudo install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/kg"
else
  rm -f "$TMP_WRAPPER"
  fail "$DEST_DIR is not writable and sudo is unavailable."
fi
rm -f "$TMP_WRAPPER"

cat <<MSG

Installed $DEST_DIR/kg

  codex --> litellm (127.0.0.1:$KG_PORT) --> $UPSTREAM_BASE_URL
             Responses            Chat Completions

  config root : $KG_HOME  (CODEX_HOME — isolated from ~/.codex)
  key file    : $KG_HOME/env
  base config : $KG_HOME/config.toml
  proxy venv  : $VENV
  proxy config: $LITELLM_YAML
  proxy log   : $KG_HOME/state/litellm.log
  model list  : $CATALOG   <- edit this to change the /model picker
  profiles    : k26 (default), k3, k27code
  default     : $DEFAULT_MODEL  (${DEFAULT_CTX} ctx)

The proxy is started by kg on launch and killed on exit. Nothing to manage.

/model should list:
MSG
for ((i = 0; i < PAIRS; i++)); do
  mark=""
  [ "${KIMI_MODELS[$i]}" = "$DEFAULT_MODEL" ] && mark=" (default)"
  printf '  %d. %-26s%s\n' "$((i + 1))" "${KIMI_MODELS[$i]}" "$mark"
done
cat <<MSG

Switch profiles:
  kg --profile k3        # kimi-k3, 1M context
  kg --profile k27code   # kimi-k2.7-code
  kg -m kimi-k3          # one-off model override

Troubleshooting:
  - If kg hangs on "starting LiteLLM", read $KG_HOME/state/litellm.log
  - Test the proxy by hand:
      . ~/.kg/env && export MOONSHOT_API_KEY
      ~/.kg/venv/bin/litellm --config ~/.kg/litellm.yaml --host 127.0.0.1 --port $KG_PORT
    then in another shell:
      curl -s http://127.0.0.1:$KG_PORT/v1/responses \\
        -H 'Content-Type: application/json' \\
        -H 'Authorization: Bearer sk-kg-local' \\
        -d '{"model":"$DEFAULT_MODEL","input":"hi"}'
  - Port in use? KG_PORT=8399 kg   (and reinstall to bake it into config.toml)
  - 404 with "url":"/v1/responses" and "ua":"litellm/..." in the log means the
    openai/chat_completions/ prefix is missing from $LITELLM_YAML.
  - A 429 "No deployments available" right after a 404 is a cooldown artifact,
    not a real rate limit. Fix the underlying error, not the retry count.
  - 401 "Incorrect API key" means the bridge works and only the upstream key
    is wrong. Update $KG_HOME/env.
MSG

# ── final env check (warn only) ──────────────────────────────────────────
KEY_OK=0
[ -n "${MOONSHOT_API_KEY:-}" ] && KEY_OK=1
grep -qs '^[[:space:]]*MOONSHOT_API_KEY=.\+' "$KG_HOME/env" && KEY_OK=1

if [ "$KEY_OK" -ne 1 ]; then
  cat >&2 <<WARN

============================================================
WARNING: MOONSHOT_API_KEY is NOT set, and $KG_HOME/env has no
usable key. \`kg\` will refuse to start until you add one:

    printf 'MOONSHOT_API_KEY=sk-xxxx\n' > $KG_HOME/env
    chmod 600 $KG_HOME/env

  Key: https://platform.moonshot.cn/console/api-keys
============================================================
WARN
fi
