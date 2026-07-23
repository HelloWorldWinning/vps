#!/usr/bin/env bash
# install-km.sh — installs /usr/local/bin/km (Claude Code + Kimi, fully isolated config)
#   default model : kimi-k2.6   (sonnet slot)
#   advanced model: kimi-k3     (opus slot, /model opus)
#   config root   : ~/.km       (separate from real Claude Code's ~/.claude)
set -euo pipefail

BASE_URL="https://api.moonshot.cn/anthropic"
DEFAULT_MODEL="kimi-k2.6"
ADVANCED_MODEL="kimi-k3"
KM_HOME="$HOME/.km"

SUDO=$([ -w /usr/local/bin ] && echo "" || echo "sudo")

command -v node >/dev/null || {
	echo "Node.js 18+ required"
	exit 1
}
command -v claude >/dev/null || npm install -g @anthropic-ai/claude-code

# --- key ----------------------------------------------------------------
if [ -z "${MOONSHOT_API_KEY:-}" ]; then
	read -rsp "Moonshot API key: " MOONSHOT_API_KEY
	echo
fi
mkdir -p "$KM_HOME"
chmod 700 "$KM_HOME"
printf 'MOONSHOT_API_KEY=%s\n' "$MOONSHOT_API_KEY" >"$KM_HOME/env"
chmod 600 "$KM_HOME/env"

# --- seed settings + shared CLAUDE.md ------------------------------------
if [ ! -e "$KM_HOME/settings.json" ]; then
	if [ -f "$HOME/.claude/settings.json" ]; then
		cp "$HOME/.claude/settings.json" "$KM_HOME/settings.json"
	else
		echo '{}' >"$KM_HOME/settings.json"
	fi
fi
if [ ! -e "$KM_HOME/CLAUDE.md" ] && [ -f "$HOME/.claude/CLAUDE.md" ]; then
	ln -s "$HOME/.claude/CLAUDE.md" "$KM_HOME/CLAUDE.md"
fi

# --- launcher ------------------------------------------------------------
$SUDO tee /usr/local/bin/km >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

export CLAUDE_CONFIG_DIR="\${KM_HOME:-\$HOME/.km}"
mkdir -p "\$CLAUDE_CONFIG_DIR"

[ -f "\$CLAUDE_CONFIG_DIR/env" ] && . "\$CLAUDE_CONFIG_DIR/env"
: "\${MOONSHOT_API_KEY:?MOONSHOT_API_KEY not set (see \$CLAUDE_CONFIG_DIR/env)}"

unset ANTHROPIC_API_KEY
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_AUTH_TOKEN="\$MOONSHOT_API_KEY"

export ANTHROPIC_DEFAULT_SONNET_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$ADVANCED_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$DEFAULT_MODEL"

export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1

exec claude --model sonnet "\$@"
EOF
$SUDO chmod +x /usr/local/bin/km

#####$SUDO rm -f /usr/local/bin/k2 /usr/local/bin/k3

cat <<MSG
Installed /usr/local/bin/km
  config root : $KM_HOME  (isolated from ~/.claude)
  key file    : $KM_HOME/env
  default     : $DEFAULT_MODEL   (sonnet slot)
  advanced    : $ADVANCED_MODEL  (opus slot — /model opus)
MSG
