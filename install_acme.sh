#!/usr/bin/env bash
set -euo pipefail

DEFAULT_EMAIL="ofwardao@gmail.com"
ACME_MANAGER="/usr/local/bin/acme-manager"

echo "======================================"
echo " ACME interactive installer / manager"
echo "======================================"
echo

#read -t 3 -rp "Email for acme.sh account [$DEFAULT_EMAIL]: " EMAIL
#EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
read -t 3 -rp "Email for acme.sh account [$DEFAULT_EMAIL]: " EMAIL || EMAIL=""
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"

echo
echo "Choose an option:"
echo "  1) Install acme.sh, then run acme-manager option 11"
echo "     Default: waits 5 seconds, then runs option 1"
echo "  2) Run acme-manager only"
echo

read -t 5 -rp "Enter choice [1]: " CHOICE || CHOICE="1"
CHOICE="${CHOICE:-1}"

echo

case "$CHOICE" in
1)
	echo "Installing acme.sh with email: $EMAIL"
	curl -fsSL https://get.acme.sh | sh -s "email=$EMAIL"

	echo
	echo "Running acme-manager option 11..."
	if [[ ! -x "$ACME_MANAGER" ]]; then
		echo "Error: $ACME_MANAGER not found or not executable."
		exit 1
	fi

	#printf '11\n' | "$ACME_MANAGER"

	CRON_JOB="17 3 * * * /usr/local/bin/acme-manager --cron >> /var/log/acme-manager.log 2>&1 # acme-manager managed cron"
	MARKER="acme-manager managed cron"

	if crontab -l 2>/dev/null | grep -qF "$MARKER"; then
		echo "Cron job already present, skipping."
	else
		echo "Installing acme-manager cron job..."
		(
			crontab -l 2>/dev/null
			echo "$CRON_JOB"
		) | crontab -
		echo "Done. Verify:"
		crontab -l | grep "$MARKER"
	fi

	;;

2)
	echo "Running acme-manager..."
	if [[ ! -x "$ACME_MANAGER" ]]; then
		echo "Error: $ACME_MANAGER not found or not executable."
		exit 1
	fi

	"$ACME_MANAGER"
	;;

*)
	echo "Invalid choice: $CHOICE"
	exit 1
	;;
esac
