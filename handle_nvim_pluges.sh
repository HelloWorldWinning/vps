#!/usr/bin/env bash
set -euo pipefail

clean_out() { tr -d '\r' | tail -n1; }

# --- Figure out which Python Neovim uses ---
# 1) If you’ve configured g:python3_host_prog, use that
PYHOST="$(nvim --headless +'echo get(g:, "python3_host_prog", "")' +q 2>/dev/null | clean_out || true)"

# 2) Otherwise, ask Neovim’s detector (no config)
if [ -z "${PYHOST:-}" ]; then
	PYHOST="$(nvim -u NONE -n --headless +'echo provider#python3#Prog()' +q 2>/dev/null | clean_out || true)"
fi

# 3) Fallback: system python3
if [ -z "${PYHOST:-}" ] && command -v python3 >/dev/null 2>&1; then
	PYHOST="$(command -v python3)"
fi

if [ -z "${PYHOST:-}" ] || [ ! -x "$PYHOST" ]; then
	echo "Error: Could not determine a usable Python for Neovim."
	echo "Tip: In Neovim run :checkhealth provider, or set g:python3_host_prog."
	exit 1
fi

echo "Neovim Python: $PYHOST"

# --- Install Python deps into THAT interpreter ---
echo "Installing/upgrading pip, pynvim, and jedi in: $PYHOST"
"$PYHOST" -m pip install --upgrade pip
"$PYHOST" -m pip install --upgrade pynvim
"$PYHOST" -m pip install --upgrade jedi
"$PYHOST" -m pip install --upgrade neovim

# --- Install Node 'neovim' (for Node.js provider) if npm exists ---
if command -v npm >/dev/null 2>&1; then
	echo "Installing/upgrading Node package 'neovim' globally (for Node provider)..."
	# If not root, you might prefer: npm install --global --prefix "$HOME/.local" neovim
	npm install -g neovim
else
	echo "Skip Node provider: npm not found in PATH."
fi

# --- (Optional) Refresh remote plugin manifest ---
echo "Refreshing Neovim remote plugin manifest..."
nvim --headless +UpdateRemotePlugins +q || true

echo "All set."
echo
echo "Verify inside Neovim:"
echo "  :checkhealth provider"
echo "  :python3 import sys, jedi; print(sys.executable, jedi.__version__)"
