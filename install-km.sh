#!/usr/bin/env bash
# install-km.sh — installs /usr/local/bin/km (Claude Code + Kimi)
#   default model : kimi-k2.6   (mapped to Sonnet slot)
#   advanced model: kimi-k3     (mapped to Opus slot, /model opus)
set -euo pipefail

BASE_URL="https://api.moonshot.cn/anthropic"
DEFAULT_MODEL="kimi-k2.6"
ADVANCED_MODEL="kimi-k3"

SUDO=$([ -w /usr/local/bin ] && echo "" || echo "sudo")

command -v node >/dev/null || {
	echo "Node.js 18+ required"
	exit 1
}
command -v claude >/dev/null || npm install -g @anthropic-ai/claude-code

if [ -z "${MOONSHOT_API_KEY:-}" ]; then
	read -rsp "Moonshot API key: " MOONSHOT_API_KEY
	echo
fi
mkdir -p "$HOME/.config/kimi-cc"
printf 'MOONSHOT_API_KEY=%s\n' "$MOONSHOT_API_KEY" >"$HOME/.config/kimi-cc/env"
chmod 600 "$HOME/.config/kimi-cc/env"

$SUDO tee /usr/local/bin/km >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
[ -f "\$HOME/.config/kimi-cc/env" ] && . "\$HOME/.config/kimi-cc/env"
: "\${MOONSHOT_API_KEY:?MOONSHOT_API_KEY not set}"

unset ANTHROPIC_API_KEY
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_AUTH_TOKEN="\$MOONSHOT_API_KEY"

# Claude-Code model slots -> Kimi models
export ANTHROPIC_DEFAULT_SONNET_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$ADVANCED_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$DEFAULT_MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$DEFAULT_MODEL"

export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1

exec claude --model sonnet "\$@"
EOF
$SUDO chmod +x /usr/local/bin/km

#######$SUDO rm -f /usr/local/bin/k2 /usr/local/bin/k3

echo "Installed /usr/local/bin/km"
echo "  default : $DEFAULT_MODEL   (sonnet slot)"
echo "  advanced: $ADVANCED_MODEL  (opus slot — switch with /model opus)"
