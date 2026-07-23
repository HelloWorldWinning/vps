#!/usr/bin/env bash
# Install isolated Claude Code launchers for Moonshot Kimi:
#   claude -> unchanged, default Claude profile (~/.claude)
#   k3     -> kimi-k3[1m], isolated Kimi profile (~/.claude-kimi)
#   k2     -> kimi-k2.6,  isolated Kimi profile (~/.claude-kimi)
set -Eeuo pipefail

DEST_DIR="${DEST_DIR:-/usr/local/bin}"
BASE_URL_DEFAULT="${MOONSHOT_ANTHROPIC_BASE_URL:-https://api.moonshot.cn/anthropic}"

log() { printf '[kimi-claude-install] %s\n' "$*"; }
fail() {
	printf '[kimi-claude-install] ERROR: %s\n' "$*" >&2
	exit 1
}

install_claude_if_missing() {
	export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"

	if command -v claude >/dev/null 2>&1; then
		log "Claude Code found: $(command -v claude)"
		return
	fi

	command -v curl >/dev/null 2>&1 || fail "curl is required to install Claude Code."
	log "Claude Code was not found; installing it..."
	curl -fsSL https://claude.ai/install.sh | bash

	export PATH="$HOME/.local/bin:$HOME/.claude/local:$PATH"
	command -v claude >/dev/null 2>&1 || fail \
		"Claude Code installation finished, but 'claude' is not on PATH."
}

ensure_dest_dir() {
	[[ -d "$DEST_DIR" ]] && return
	if mkdir -p "$DEST_DIR" 2>/dev/null; then
		return
	fi
	command -v sudo >/dev/null 2>&1 || fail \
		"Cannot create $DEST_DIR and sudo is unavailable."
	sudo mkdir -p "$DEST_DIR"
}

install_wrapper() {
	local command_name="$1"
	local model="$2"
	local context_window="$3"
	local tmp
	tmp="$(mktemp)"

	cat >"$tmp" <<EOF_WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail

MODEL='$model'
CONTEXT_WINDOW='$context_window'
BASE_URL="\${MOONSHOT_ANTHROPIC_BASE_URL:-${BASE_URL_DEFAULT}}"
API_KEY="\${MOONSHOT_API_KEY:-}"

# Separate Kimi's user-level configuration, credentials, history, plugins,
# and session state from the normal Claude Code profile.
export CLAUDE_CONFIG_DIR="\${KIMI_CLAUDE_CONFIG_DIR:-\$HOME/.claude-kimi}"
mkdir -p "\$CLAUDE_CONFIG_DIR"
chmod 700 "\$CLAUDE_CONFIG_DIR" 2>/dev/null || true

if [[ -z "\$API_KEY" ]]; then
  cat >&2 <<'EOF_ERROR'
MOONSHOT_API_KEY is not set.

Set it, then run this command again:
  export MOONSHOT_API_KEY='sk-...'
EOF_ERROR
  exit 2
fi

export PATH="\$HOME/.local/bin:\$HOME/.claude/local:\$PATH"
command -v claude >/dev/null 2>&1 || {
  echo "Claude Code ('claude') is not available on PATH." >&2
  exit 127
}

# Avoid the dual-credential warning and route only this process to Moonshot.
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="\$BASE_URL"
export ANTHROPIC_AUTH_TOKEN="\$API_KEY"

# Pin all Claude Code model roles to the selected Kimi model.
export ANTHROPIC_MODEL="\$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_FABLE_MODEL="\$MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="\$MODEL"

export ENABLE_TOOL_SEARCH="\${ENABLE_TOOL_SEARCH:-false}"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="\${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-\$CONTEXT_WINDOW}"
export CLAUDE_CODE_EFFORT_LEVEL="\${CLAUDE_CODE_EFFORT_LEVEL:-max}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="\${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
export API_TIMEOUT_MS="\${API_TIMEOUT_MS:-600000}"

# Initialize onboarding only inside the isolated Kimi profile. Never edit
# ~/.claude.json or ~/.claude/settings.json.
python3 - "\$CLAUDE_CONFIG_DIR/.claude.json" <<'PY' 2>/dev/null || true
import json
import os
import sys
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

# CLI model selection has higher precedence than user/project settings.
exec claude --model "\$MODEL" "\$@"
EOF_WRAPPER

	chmod 0755 "$tmp"
	if [[ -w "$DEST_DIR" ]]; then
		install -m 0755 "$tmp" "$DEST_DIR/$command_name"
	elif command -v sudo >/dev/null 2>&1; then
		sudo install -m 0755 "$tmp" "$DEST_DIR/$command_name"
	else
		rm -f "$tmp"
		fail "$DEST_DIR is not writable and sudo is unavailable."
	fi
	rm -f "$tmp"
	log "Installed $DEST_DIR/$command_name -> $model"
}

install_claude_if_missing
ensure_dest_dir
install_wrapper k3 'kimi-k3[1m]' 1048576
install_wrapper k2 'kimi-k2.6' 262144

cat <<EOF_DONE

Installation complete.

Profiles:
  claude -> \$HOME/.claude       (unchanged native Claude profile)
  k2/k3  -> \$HOME/.claude-kimi  (isolated shared Kimi profile)

Set the Moonshot key:
  export MOONSHOT_API_KEY='sk-...'

Launch:
  k3
  k2

Verify inside each Kimi session with /status:
  Config directory: \$HOME/.claude-kimi
  Base URL: ${BASE_URL_DEFAULT}

Optional custom Kimi profile location:
  export KIMI_CLAUDE_CONFIG_DIR='\$HOME/.config/claude-kimi'
EOF_DONE
