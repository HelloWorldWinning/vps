#!/usr/bin/env bash

#17 3 * * * /usr/local/sbin/acme-outline-renew.sh >> /var/log/acme-manager.log 2>&1 # acme-manager with Outline stop/up every 4 days

STACK_FILE="/root/Outline_D/docker-compose.yml"
STAMP_FILE="/var/lib/acme-manager/last-outline-renew"
LOCK_FILE="/run/acme-outline-renew.lock"
INTERVAL_SECONDS=$((4 * 24 * 60 * 60))

mkdir -p "$(dirname "$STAMP_FILE")"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	echo "$(date -Is) another acme-outline-renew job is already running; exiting"
	exit 0
fi

now="$(date +%s)"
last=0

if [ -s "$STAMP_FILE" ]; then
	last="$(cat "$STAMP_FILE" 2>/dev/null || echo 0)"
fi

if [ "$((now - last))" -lt "$INTERVAL_SECONDS" ]; then
	echo "$(date -Is) less than 4 days since last acme-manager run; skipping"
	exit 0
fi

if docker compose version >/dev/null 2>&1; then
	COMPOSE=(docker compose -f "$STACK_FILE")
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE=(docker-compose -f "$STACK_FILE")
else
	echo "$(date -Is) ERROR: docker compose / docker-compose not found"
	exit 1
fi

cleanup() {
	rc=$?
	trap - EXIT

	echo "$(date -Is) starting Outline docker compose again"
	"${COMPOSE[@]}" up -d
	up_rc=$?

	if [ "$up_rc" -ne 0 ]; then
		echo "$(date -Is) ERROR: docker compose up -d failed with exit code $up_rc"
		exit "$up_rc"
	fi

	exit "$rc"
}

trap cleanup EXIT INT TERM

echo "$(date -Is) stopping Outline docker compose"
"${COMPOSE[@]}" stop

echo "$(date -Is) running acme-manager --cron"
/usr/local/bin/acme-manager --cron
acme_rc=$?

echo "$(date +%s)" >"$STAMP_FILE"

if [ "$acme_rc" -ne 0 ]; then
	echo "$(date -Is) WARNING: acme-manager failed with exit code $acme_rc"
else
	echo "$(date -Is) acme-manager completed successfully"
fi

exit "$acme_rc"
