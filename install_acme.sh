#!/usr/bin/env bash
set -euo pipefail

DEFAULT_EMAIL="ofwardao@gmail.com"
ACME_MANAGER="/usr/local/bin/acme-manager"
ACME_MANAGER_URL="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/acme-manager"
CRON_JOB="17 3 * * * /usr/local/bin/acme-manager --cron >> /var/log/acme-manager.log 2>&1 # acme-manager managed cron"
MARKER="acme-manager managed cron"

echo "======================================"
echo " ACME interactive installer / manager"
echo "======================================"
echo

read -t 3 -rp "Email for acme.sh account [$DEFAULT_EMAIL]: " EMAIL || EMAIL=""
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"

echo
echo "Choose an option:"
echo "  1) Install acme.sh + acme-manager + cron  [default]"
echo "  2) Run acme-manager only"
echo

read -t 5 -rp "Enter choice [1]: " CHOICE || CHOICE="1"
CHOICE="${CHOICE:-1}"

echo

# ── helper: install acme-manager binary if missing ──────────────────────────
ensure_acme_manager() {
	if [[ ! -x "$ACME_MANAGER" ]]; then
		echo "acme-manager not found. Downloading..."
		curl -fsSL "$ACME_MANAGER_URL" -o "$ACME_MANAGER"
		chmod +x "$ACME_MANAGER"
		echo "acme-manager installed at $ACME_MANAGER"
	else
		echo "acme-manager already present."
	fi
}

# ── helper: install cron directly, no interactive menu needed ───────────────
install_cron() {
	if crontab -l 2>/dev/null | grep -qF "$MARKER"; then
		echo "Cron job already present, skipping."
	else
		echo "Installing acme-manager cron job..."
		(
			crontab -l 2>/dev/null
			echo "$CRON_JOB"
		) | crontab -
		echo "Done. Current crontab entry:"
		crontab -l | grep "$MARKER"
	fi
}

case "$CHOICE" in
1)
	# 1) install acme.sh
	echo "Installing acme.sh with email: $EMAIL"
	curl -fsSL https://get.acme.sh | sh -s "email=$EMAIL"
	echo

	# 2) install acme-manager if missing
	ensure_acme_manager
	echo

	# 3) install cron directly (no interactive pipe)
	install_cron
	;;

2)
	ensure_acme_manager
	"$ACME_MANAGER"
	;;

*)
	echo "Invalid choice: $CHOICE"
	exit 1
	;;
esac
