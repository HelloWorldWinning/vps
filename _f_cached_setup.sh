#!/bin/bash

set -e

SCRIPT_URL="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/goodv3.sh"
CACHED_SCRIPT="$HOME/.cached_f_script.sh"
CRON_JOB="0 * * * * curl -Ls4 $SCRIPT_URL > $CACHED_SCRIPT 2>/dev/null"

echo "=== Step 1: Downloading script to $CACHED_SCRIPT ==="
curl -Ls4 "$SCRIPT_URL" > "$CACHED_SCRIPT" 2>/dev/null || {
    echo "Error: Failed to download script"
    exit 1
}
chmod +x "$CACHED_SCRIPT"
echo "✓ Script downloaded successfully"

echo ""
echo "=== Step 2: Setting up crontab job ==="
# Check if cron job already exists
if crontab -l 2>/dev/null | grep -Fq "$CACHED_SCRIPT"; then
    echo "✓ Crontab job already exists, skipping"
else
    # Add cron job (refresh every hour at minute 0)
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✓ Crontab job added successfully"
fi

echo ""
echo "=== Step 3: Setting up alias in ~/.bashrc ==="
ALIAS_LINE="alias f='bash $CACHED_SCRIPT'"

# Comment out old alias lines containing "alias f="
if grep -q "^alias f=" "$HOME/.bashrc" 2>/dev/null; then
    sed -i "s/^alias f=/# alias f=/" "$HOME/.bashrc"
    echo "✓ Old alias(es) commented out"
fi

# Add new alias
echo "" >> "$HOME/.bashrc"
echo "# Auto-generated alias for cached script" >> "$HOME/.bashrc"
echo "$ALIAS_LINE" >> "$HOME/.bashrc"
echo "✓ New alias added to ~/.bashrc"

echo ""
echo "=== Setup Complete ==="
echo "✓ Alias configured successfully"
echo ""
echo "Run the following command to activate:"
echo "  source ~/.bashrc"
echo ""
echo "Then you can use: f"
