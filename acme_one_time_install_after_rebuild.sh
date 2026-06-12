#!/usr/bin/env bash
set -euo pipefail

EMAIL="ofwardao@gmail.com"
ACME_MANAGER="/usr/local/bin/acme-manager"
CRON_JOB="17 3 * * * /usr/local/bin/acme-manager --cron >> /var/log/acme-manager.log 2>&1 # acme-manager managed cron"
MARKER="acme-manager managed cron"

echo "Installing acme.sh with email: $EMAIL"
curl -fsSL https://get.acme.sh | sh -s "email=$EMAIL"

echo "Installing acme-manager to $ACME_MANAGER ..."
cat >"$ACME_MANAGER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ACME_SH="/root/.acme.sh/acme.sh"
LOG="/var/log/acme-manager.log"
stop_services() {
  systemctl stop nginx 2>/dev/null || true
  systemctl stop xray 2>/dev/null || true
  if [[ -f /root/xray_docker_d/docker-compose.yml ]]; then
    docker-compose -f /root/xray_docker_d/docker-compose.yml down 2>/dev/null || true
  fi
}
start_services() {
  if [[ -f /root/xray_docker_d/docker-compose.yml ]]; then
    docker-compose -f /root/xray_docker_d/docker-compose.yml up -d 2>/dev/null || true
  fi
  systemctl start nginx 2>/dev/null || true
  systemctl start xray 2>/dev/null || true
}
run_cron() {
  echo "===== $(date) acme-manager cron start ====="
  stop_services
  sleep 5
  if [[ -x "$ACME_SH" ]]; then
    "$ACME_SH" --cron --home /root/.acme.sh
  else
    echo "ERROR: acme.sh not found at $ACME_SH"
  fi
  sleep 5
  start_services
  echo "===== $(date) acme-manager cron end ====="
}
interactive_menu() {
  echo "acme-manager"
  echo
  echo "1) Run acme.sh renewal now"
  echo "2) Show certificates"
  echo "3) Exit"
  echo
  read -rp "Choice [1]: " choice
  choice="${choice:-1}"
  case "$choice" in
    1) run_cron ;;
    2)
      if [[ -x "$ACME_SH" ]]; then
        "$ACME_SH" --list
      else
        echo "acme.sh not found at $ACME_SH"
      fi
      ;;
    3) exit 0 ;;
    *) echo "Invalid choice: $choice"; exit 1 ;;
  esac
}
case "${1:-}" in
  --cron)
    run_cron >> "$LOG" 2>&1
    ;;
  *)
    interactive_menu
    ;;
esac
EOF
chmod +x "$ACME_MANAGER"
echo "acme-manager installed."

echo "Installing acme-manager cron job..."
TMP_CRON=$(mktemp)
crontab -l 2>/dev/null | grep -vF "$MARKER" >"$TMP_CRON" || true
echo "$CRON_JOB" >>"$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true

echo "Done. Current crontab:"
crontab -l | grep "$MARKER"
echo "acme_one_time_install_after_rebuild.sh finished at $(date)"
