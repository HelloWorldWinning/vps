#!/usr/bin/env bash
set -Eeuo pipefail

# ===== temporary workspace =====

OLD_TMPDIR="${TMPDIR:-}"

mkdir -p ~/.tmp
chmod 700 ~/.tmp

export TMPDIR="$HOME/.tmp"

cleanup_tmp() {
	rm -rf "$HOME/.tmp"

	if [ -n "$OLD_TMPDIR" ]; then
		export TMPDIR="$OLD_TMPDIR"
	else
		unset TMPDIR
	fi

	unset OLD_TMPDIR
}

trap cleanup_tmp EXIT

# Complete Neovim + Miniconda + Python provider installer.
# It installs pynvim into a dedicated Python venv and tells Neovim exactly which Python to use.

MINICONDA_DIR="${MINICONDA_DIR:-$HOME/miniconda3}"
NVIM_PY_ENV="${NVIM_PY_ENV:-$HOME/.venvs/nvim-python}"
MINICONDA_URL="${MINICONDA_URL:-https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh}"

echo "==> Home: $HOME"
echo "==> Miniconda directory: $MINICONDA_DIR"
echo "==> Neovim Python env: $NVIM_PY_ENV"

# --------------------------------------------------------------------
# 1. Install Miniconda if missing
# --------------------------------------------------------------------
if [ ! -x "$MINICONDA_DIR/bin/python" ]; then
	echo "==> Installing Miniconda..."

	mkdir -p "$MINICONDA_DIR"

	#tmp_installer="$(mktemp /tmp/miniconda.XXXXXX.sh)"
	tmp_installer="$(mktemp "$HOME/.tmp/miniconda.XXXXXX.sh")"
	cleanup() {
		rm -f "$tmp_installer"
	}
	trap cleanup EXIT

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$MINICONDA_URL" -o "$tmp_installer"
	elif command -v wget >/dev/null 2>&1; then
		wget -q "$MINICONDA_URL" -O "$tmp_installer"
	else
		echo "ERROR: neither curl nor wget is installed." >&2
		exit 1
	fi

	bash "$tmp_installer" -b -u -p "$MINICONDA_DIR"
else
	echo "==> Miniconda already installed."
fi

# --------------------------------------------------------------------
# 2. Initialize conda for bash, but do not rely on shell activation here
# --------------------------------------------------------------------
echo "==> Initializing conda for bash..."
"$MINICONDA_DIR/bin/conda" init bash || true

# --------------------------------------------------------------------
# 3. Update base pip tooling
# --------------------------------------------------------------------
echo "==> Updating base Python pip tooling..."
"$MINICONDA_DIR/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
"$MINICONDA_DIR/bin/python" -m pip install --upgrade pip setuptools wheel

# --------------------------------------------------------------------
# 4. Create a dedicated Python environment for Neovim's Python provider
# --------------------------------------------------------------------
echo "==> Creating/updating dedicated Neovim Python environment..."

if [ ! -x "$NVIM_PY_ENV/bin/python" ]; then
	"$MINICONDA_DIR/bin/python" -m venv "$NVIM_PY_ENV"
fi

"$NVIM_PY_ENV/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
"$NVIM_PY_ENV/bin/python" -m pip install --upgrade pip setuptools wheel
"$NVIM_PY_ENV/bin/python" -m pip install --upgrade pynvim jedi

echo "==> Verifying pynvim import..."
"$NVIM_PY_ENV/bin/python" -c 'import sys, pynvim; print("Python:", sys.executable); print("pynvim:", pynvim.__version__)'

# --------------------------------------------------------------------
# 5. Configure Neovim to use the exact Python environment
# --------------------------------------------------------------------
echo "==> Configuring Neovim python3_host_prog..."

NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
mkdir -p "$NVIM_CONFIG_DIR"

INIT_LUA="$NVIM_CONFIG_DIR/init.lua"
INIT_VIM="$NVIM_CONFIG_DIR/init.vim"

PY_ESCAPED="$NVIM_PY_ENV/bin/python"

if [ -f "$INIT_LUA" ] || [ ! -f "$INIT_VIM" ]; then
	# Prefer init.lua if it exists, or if no config exists yet.
	touch "$INIT_LUA"

	if grep -q "python3_host_prog" "$INIT_LUA"; then
		echo "==> init.lua already contains python3_host_prog. Please verify it points to:"
		echo "    $PY_ESCAPED"
	else
		{
			echo ""
			echo "-- Python provider for Neovim"
			echo "vim.g.python3_host_prog = '$PY_ESCAPED'"
		} >>"$INIT_LUA"
		echo "==> Added python3_host_prog to $INIT_LUA"
	fi
else
	touch "$INIT_VIM"

	if grep -q "python3_host_prog" "$INIT_VIM"; then
		echo "==> init.vim already contains python3_host_prog. Please verify it points to:"
		echo "    $PY_ESCAPED"
	else
		{
			echo ""
			echo '" Python provider for Neovim'
			echo "let g:python3_host_prog = '$PY_ESCAPED'"
		} >>"$INIT_VIM"
		echo "==> Added python3_host_prog to $INIT_VIM"
	fi
fi

# --------------------------------------------------------------------
# 6. Install Node tooling for TypeScript LSP, if npm exists
# --------------------------------------------------------------------
if command -v npm >/dev/null 2>&1; then
	echo "==> Installing TypeScript language server..."
	npm install -g typescript-language-server typescript
else
	echo "==> npm not found. Skipping TypeScript language server install."
fi

# --------------------------------------------------------------------
# 7. Optional Neovim health check / remote plugin update
# --------------------------------------------------------------------
if command -v nvim >/dev/null 2>&1; then
	echo "==> Running Neovim provider health check..."
	nvim --headless '+checkhealth provider' '+qa' || true

	echo "==> Updating remote plugins..."
	nvim --headless '+UpdateRemotePlugins' '+qa' || true
else
	echo "==> nvim not found in PATH. Skipping Neovim checks."
fi

cat <<EOF

DONE.

Next steps:
1. Restart your shell:
   exec bash

2. Open Neovim and run:
   :checkhealth provider

Expected Python provider:
   $NVIM_PY_ENV/bin/python

If you previously had this broken value in your config:
   let g:python3_host_prog = v:null

remove it or replace it with:
   let g:python3_host_prog = '$NVIM_PY_ENV/bin/python'

EOF
