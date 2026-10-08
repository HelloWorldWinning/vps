#!/usr/bin/env bash
# jupyter-firewall.sh
#
# Only allow Jupyter's port through the NetBird interface (wt0) and drop it
# everywhere else, then persist the rules across reboots.
#
# Usage (as root):
#   bash jupyter-firewall.sh            # add rules + persist (default)
#   bash jupyter-firewall.sh status     # show the matching rules
#   bash jupyter-firewall.sh remove     # delete the rules + persist
#
# Override defaults with env vars:
#   PORT=16666 NB_IF=wt0 bash jupyter-firewall.sh
#
# Only port $PORT is touched, so SSH and other services are not affected.
# Safe to re-run: it removes its own rules first, so no duplicates build up.

set -euo pipefail

PORT="${PORT:-16666}"
NB_IF="${NB_IF:-wt0}"          # NetBird interface name (check: ip -br addr | grep 100.0.0.)
ACTION="${1:-apply}"

info() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0"
command -v iptables >/dev/null 2>&1 || die "iptables not found"

# Rule bodies. The same arrays are used to check, insert and delete,
# so the three operations can never drift apart.
#   1) loopback may reach the port (VPS -> itself, SSH tunnels to localhost)
#   2) everything not arriving on the NetBird interface is dropped
LO_ARGS=(-i lo -p tcp --dport "$PORT" -j ACCEPT)
DROP_ARGS=(-p tcp --dport "$PORT" ! -i "$NB_IF" -j DROP)

have_rule() { iptables -C INPUT "$@" 2>/dev/null; }
del_rule()  { while have_rule "$@"; do iptables -D INPUT "$@"; done; }

check_other_firewalls() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    die "ufw is active. Manage this with ufw instead:
       ufw allow in on $NB_IF to any port $PORT proto tcp
       ufw deny $PORT/tcp"
  fi
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    die "firewalld is active. Use firewall-cmd rules instead of this script."
  fi
}

backup_rules() {
  local f="/root/iptables-before-$(date +%F_%H%M%S).rules"
  iptables-save > "$f"
  info "backup of current rules: $f"
}

persist() {
  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      info "installing iptables-persistent"
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    else
      warn "no persistence tool known for this distro: rules are ACTIVE but will be lost at reboot"
      return 0
    fi
  fi
  netfilter-persistent save
  systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  if grep -q -- "--dport $PORT" /etc/iptables/rules.v4 2>/dev/null; then
    info "persisted in /etc/iptables/rules.v4"
  else
    warn "rule not found in /etc/iptables/rules.v4 after save: check manually"
  fi
}

show_status() {
  info "INPUT rules for port $PORT:"
  iptables -L INPUT -n -v --line-numbers | grep -E "^num|dpt:$PORT" || echo "(none)"
}

do_apply() {
  check_other_firewalls
  ip link show "$NB_IF" >/dev/null 2>&1 \
    || die "interface '$NB_IF' not found. Find it with: ip -br addr | grep 100.0.0.   then run: NB_IF=<name> bash $0"

  backup_rules

  # Remove our own rules first (idempotent), then insert in the right order.
  del_rule "${DROP_ARGS[@]}"
  del_rule "${LO_ARGS[@]}"

  iptables -I INPUT 1 "${DROP_ARGS[@]}"   # inserted first -> ends up at position 2
  iptables -I INPUT 1 "${LO_ARGS[@]}"     # inserted second -> position 1, checked before the drop

  show_status
  persist

  cat <<EOF

Done. Test it:
  on the VPS            : curl -sI http://127.0.0.1:$PORT/ | head -1   (only works if Jupyter listens on 0.0.0.0 or 127.0.0.1)
  from a NetBird peer   : http://<this-vps-netbird-ip>:$PORT/          (should load)
  from outside NetBird  : nc -zv <vps-public-ip> $PORT                 (should time out)
EOF
}

do_remove() {
  del_rule "${DROP_ARGS[@]}"
  del_rule "${LO_ARGS[@]}"
  info "rules removed"
  show_status
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  fi
}

case "$ACTION" in
  apply)  do_apply ;;
  remove) do_remove ;;
  status) show_status ;;
  *)      die "unknown action '$ACTION' (use: apply | status | remove)" ;;
esac
