#!/usr/bin/env bash
# install-km.sh — installs /usr/local/bin/km (Claude Code + Kimi, fully isolated config)
#
#   default model : kimi-k2.6     (sonnet + haiku slots, subagents, background tasks)
#   advanced model: kimi-k3[1m]   (opus slot — switch in-session with /model opus)
#   config root   : ~/.km         (fully separate from real Claude Code's ~/.claude)
#
# In-session switching (this is why ANTHROPIC_MODEL is deliberately NOT set):
#   /model sonnet  -> kimi-k2.6
#   /model opus    -> kimi-k3[1m]
set -Eeuo pipefail

BASE_URL_DEFAULT="${MOONSHOT_ANTHROPIC_BASE_URL:-https://api.moonshot.cn/anthropic}"
DEFAULT_MODEL="kimi-k2.6"
ADVANCED_MODEL="kimi-k3[1m]"
KM_HOME="${KM_HOME:-$HOME/.km}"
DEST_DIR="${DEST_DIR:-/usr/local/bin}"

log()  { printf '[km-install] %s\n' "$*"; }
fail() { printf '[km-install] ERROR: %s\n' "$*" >&2; exit 1; }

# --- claude binary -------------------------------------------------------
export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
if ! command -v claude >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    log "Installing Claude Code via npm..."
    npm install -g @anthropic-ai/claude-code
  elif command -v curl >/dev/null 2>&1; then
    log "Installing Claude Code via native installer..."
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
  else
    fail "Neither npm nor curl available; install Claude Code manually first."
  fi
fi
command -v claude >/dev/null 2>&1 || fail "'claude' still not on PATH after install."
log "Claude Code found: $(command -v claude)"

# --- key -----------------------------------------------------------------
if [ -z "${MOONSHOT_API_KEY:-}" ]; then
  read -rsp "Moonshot API key: " MOONSHOT_API_KEY
  echo
fi
[ -n "$MOONSHOT_API_KEY" ] || fail "Empty API key."
mkdir -p "$KM_HOME"
chmod 700 "$KM_HOME"
printf 'MOONSHOT_API_KEY=%s\n' "$MOONSHOT_API_KEY" > "$KM_HOME/env"
chmod 600 "$KM_HOME/env"

# --- seed settings.json (copy from ~/.claude but STRIP the "env" field) --
# Rationale: settings.json "env" OVERRIDES shell-exported variables
# (per Kimi docs). If the real Claude profile ever carries env entries,
# a raw copy would silently override km's Moonshot routing.
if [ ! -e "$KM_HOME/settings.json" ]; then
  if [ -f "$HOME/.claude/settings.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$HOME/.claude/settings.json" "$KM_HOME/settings.json" <<'PY' || echo '{}' > "$KM_HOME/settings.json"
import json, sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
data = json.loads(src.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    data = {}
# Never inherit env overrides or API key helpers from the real profile.
data.pop("env", None)
data.pop("apiKeyHelper", None)
dst.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  else
    echo '{}' > "$KM_HOME/settings.json"
  fi
  chmod 600 "$KM_HOME/settings.json" 2>/dev/null || true
fi

# Share the user-level CLAUDE.md (read-only intent) via symlink, if present.
if [ ! -e "$KM_HOME/CLAUDE.md" ] && [ -f "$HOME/.claude/CLAUDE.md" ]; then
  ln -s "$HOME/.claude/CLAUDE.md" "$KM_HOME/CLAUDE.md"
fi

# --- launcher ------------------------------------------------------------
TMP_WRAPPER="$(mktemp)"
cat > "$TMP_WRAPPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

# --- isolated profile (never touches ~/.claude or ~/.claude.json) --------
export CLAUDE_CONFIG_DIR="\${KM_HOME:-\$HOME/.km}"
mkdir -p "\$CLAUDE_CONFIG_DIR"
chmod 700 "\$CLAUDE_CONFIG_DIR" 2>/dev/null || true

[ -f "\$CLAUDE_CONFIG_DIR/env" ] && . "\$CLAUDE_CONFIG_DIR/env"
: "\${MOONSHOT_API_KEY:?MOONSHOT_API_KEY not set (see \$CLAUDE_CONFIG_DIR/env)}"

export PATH="\$HOME/.local/bin:\$HOME/.claude/local:\$PATH"
command -v claude >/dev/null 2>&1 || { echo "'claude' not on PATH" >&2; exit 127; }

# --- credentials: clear both, then set only what we need ------------------
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="\${MOONSHOT_ANTHROPIC_BASE_URL:-$BASE_URL_DEFAULT}"
export ANTHROPIC_AUTH_TOKEN="\$MOONSHOT_API_KEY"

# --- model slots ----------------------------------------------------------
# ANTHROPIC_MODEL is deliberately NOT exported: setting it would pin the
# model and break in-session /model sonnet|opus switching.
export ANTHROPIC_DEFAULT_SONNET_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$ADVANCED_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_DEFAULT_FABLE_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$DEFAULT_MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$DEFAULT_MODEL"

# --- Kimi-endpoint requirements & tuning ---------------------------------
# Tool Search is unsupported on the Kimi endpoint; must be off.
export ENABLE_TOOL_SEARCH="\${ENABLE_TOOL_SEARCH:-false}"
# One global value must be safe for BOTH slots. kimi-k2.6 = 256K context,
# so 262144 is the safe ceiling. If you switch to k3-only usage, override:
#   CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576 km
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="\${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-262144}"
export CLAUDE_CODE_EFFORT_LEVEL="\${CLAUDE_CODE_EFFORT_LEVEL:-max}"
export API_TIMEOUT_MS="\${API_TIMEOUT_MS:-600000}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="\${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
export DISABLE_TELEMETRY="\${DISABLE_TELEMETRY:-1}"

# --- skip onboarding/login prompt inside the isolated profile only --------
python3 - "\$CLAUDE_CONFIG_DIR/.claude.json" <<'PY' 2>/dev/null || true
import json, os, sys
from pathlib import Path
path = Path(sys.argv[1])
data = {}
if path.exists():
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        pass
data["hasCompletedOnboarding"] = True
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
try:
    os.chmod(path, 0o600)
except OSError:
    pass
PY

# Start on the sonnet slot (kimi-k2.6); /model opus switches to kimi-k3[1m].
exec claude --model sonnet "\$@"
EOF
chmod 0755 "$TMP_WRAPPER"

if [ -w "$DEST_DIR" ]; then
  install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/km"
elif command -v sudo >/dev/null 2>&1; then
  sudo install -m 0755 "$TMP_WRAPPER" "$DEST_DIR/km"
else
  rm -f "$TMP_WRAPPER"
  fail "$DEST_DIR is not writable and sudo is unavailable."
fi
rm -f "$TMP_WRAPPER"

cat <<MSG

Installed $DEST_DIR/km
  config root : $KM_HOME  (isolated — never touches ~/.claude or ~/.claude.json)
  key file    : $KM_HOME/env
  sonnet slot : $DEFAULT_MODEL   (default on launch, subagents, background)
  opus slot   : $ADVANCED_MODEL  (switch with /model opus)

Verify inside a km session with /status:
  Config directory: $KM_HOME
  Base URL: $BASE_URL_DEFAULT
  Model: $DEFAULT_MODEL

Notes:
  - /model menu shows built-in alias names only; trust /status, not the menu.
  - If you swap a slot to kimi-k2.7-code, keep Thinking ON (press Tab),
    otherwise requests fail with 400 invalid thinking.
MSG
