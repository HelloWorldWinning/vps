#!/usr/bin/env bash
# $HOME/netbird-hosts_install.sh
#
# Debian installer for NetBird /etc/hosts auto updater.
#
# This installer:
#   1. Installs /usr/local/bin/netbird-hosts.sh
#   2. Adds or replaces a tagged root crontab block
#   3. Runs every 10 minutes
#   4. Updates only the managed NetBird block in /etc/hosts
#   5. Skips /etc/hosts writes when NetBird DNS entries have not changed
#
# Run as your normal $HOME user:
#   chmod +x $HOME/netbird-hosts_install.sh
#   $HOME/netbird-hosts_install.sh

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

TARGET_SCRIPT="${TARGET_SCRIPT:-/usr/local/bin/netbird-hosts.sh}"
#LOG_FILE="${LOG_FILE:-/var/log/netbird-hosts.log}"
LOG_FILE="${LOG_FILE:-/tmp/netbird-hosts.log}"

CRON_BEGIN="# BEGIN NETBIRD HOSTS CRON"
CRON_END="# END NETBIRD HOSTS CRON"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/10 * * * *}"
CRON_LINE="${CRON_SCHEDULE} ${TARGET_SCRIPT} >> ${LOG_FILE} 2>&1"

INSTALL_DEPS="${INSTALL_DEPS:-1}"
RUN_ON_INSTALL="${RUN_ON_INSTALL:-1}"

if [[ "$(id -u)" -eq 0 ]]; then
	SUDO=()
else
	if ! command -v sudo >/dev/null 2>&1; then
		echo "ERROR: sudo is required when running as a normal user."
		exit 1
	fi
	sudo -v
	SUDO=(sudo)
fi

if [[ ! -r /etc/debian_version ]]; then
	echo "WARNING: /etc/debian_version not found. This script is intended for Debian."
fi

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

install_deps_if_needed() {
	local missing=()

	if ! need_cmd jq; then
		missing+=("jq")
	fi

	if ! need_cmd crontab; then
		missing+=("cron")
	fi

	if [[ "${#missing[@]}" -gt 0 ]]; then
		if [[ "$INSTALL_DEPS" == "1" ]]; then
			if ! need_cmd apt-get; then
				echo "ERROR: Missing commands/packages: ${missing[*]}"
				echo "ERROR: apt-get not found, cannot auto-install dependencies."
				exit 1
			fi

			echo "Installing missing dependencies: ${missing[*]}"
			"${SUDO[@]}" apt-get update
			"${SUDO[@]}" apt-get install -y "${missing[@]}"

			if command -v systemctl >/dev/null 2>&1; then
				"${SUDO[@]}" systemctl enable --now cron >/dev/null 2>&1 || true
			else
				"${SUDO[@]}" service cron start >/dev/null 2>&1 || true
			fi
		else
			echo "ERROR: Missing commands/packages: ${missing[*]}"
			echo "Install them first, or run with INSTALL_DEPS=1."
			exit 1
		fi
	fi

	if ! need_cmd jq; then
		echo "ERROR: jq is still not available after dependency install."
		exit 1
	fi

	if ! need_cmd crontab; then
		echo "ERROR: crontab is still not available after dependency install."
		exit 1
	fi
}

check_netbird_exists() {
	if ! need_cmd netbird; then
		echo "ERROR: netbird command not found."
		echo "Install NetBird first, then re-run this installer."
		exit 1
	fi
}

install_runtime_script() {
	echo "Installing ${TARGET_SCRIPT}"

	"${SUDO[@]}" install -d -m 0755 "$(dirname "$TARGET_SCRIPT")"

	"${SUDO[@]}" tee "$TARGET_SCRIPT" >/dev/null <<'NETBIRD_HOSTS_RUNTIME'
#!/usr/bin/env bash
# /usr/local/bin/netbird-hosts.sh
#
# Updates only the managed NetBird block in /etc/hosts.
# Safe to run from root cron.
# Debian/Linux version.

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

HOSTS="${HOSTS:-/etc/hosts}"
BACKUP="${BACKUP:-/etc/hosts.netbird.bak}"

BEGIN="# BEGIN NETBIRD AUTO HOSTS"
END="# END NETBIRD AUTO HOSTS"

LOCKDIR="${LOCKDIR:-/run/lock/netbird-hosts.lock}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: must run as root because /etc/hosts must be modified."
  exit 1
fi

if [[ ! -f "$HOSTS" ]]; then
  echo "ERROR: ${HOSTS} does not exist."
  exit 1
fi

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another netbird-hosts.sh run is active; skip."
  exit 0
fi

TMPDIR="$(mktemp -d)"
tmp_json="${TMPDIR}/netbird-status.json"
tmp_entries="${TMPDIR}/entries"
tmp_current_entries="${TMPDIR}/current-entries"
tmp_block="${TMPDIR}/block"
tmp_hosts="${TMPDIR}/hosts"

cleanup() {
  rm -rf "$TMPDIR"
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

NETBIRD="$(command -v netbird || true)"
JQ="$(command -v jq || true)"

if [[ -z "$NETBIRD" ]]; then
  echo "ERROR: netbird command not found"
  exit 1
fi

if [[ -z "$JQ" ]]; then
  echo "ERROR: jq command not found"
  exit 1
fi

if ! "$NETBIRD" status --json > "$tmp_json"; then
  echo "WARNING: netbird status failed; keep existing ${HOSTS}"
  exit 0
fi

"$JQ" -r '
  def cleanstr:
    tostring
    | gsub("^[[:space:]]+"; "")
    | gsub("[[:space:]]+$"; "");

  def peerlist:
    if (.peers.details? | type) == "array" then
      .peers.details
    elif (.peers? | type) == "array" then
      .peers
    elif (.Peers.Details? | type) == "array" then
      .Peers.Details
    else
      []
    end;

  peerlist
  | .[]
  | (.netbirdIp // .netbird_ip // .netBirdIp // .NetbirdIp // .ip // .IP // "") as $raw_ip
  | (.fqdn // .FQDN // .Fqdn // .dnsName // .hostname // .name // "") as $raw_fqdn
  | ($raw_ip | cleanstr) as $ip
  | ($raw_fqdn | cleanstr | ascii_downcase | sub("\\.$"; "")) as $fqdn
  | select($ip != "" and $fqdn != "")
  | select($fqdn | test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$"))
  | ($fqdn | split(".")[0]) as $short
  | if $short != "" and $short != $fqdn then
      "\($ip)\t\($short)\t\($fqdn)"
    else
      "\($ip)\t\($fqdn)"
    end
' "$tmp_json" | LC_ALL=C sort -u > "$tmp_entries"

entry_count="$(wc -l < "$tmp_entries" | tr -d ' ')"

if [[ "$entry_count" -eq 0 ]]; then
  echo "WARNING: NetBird returned 0 DNS entries; keep existing ${HOSTS}"
  exit 0
fi

awk -v begin="$BEGIN" -v end="$END" '
  $0 == begin { inblock=1; next }
  $0 == end { inblock=0; next }
  inblock == 1 && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ { print }
' "$HOSTS" | LC_ALL=C sort -u > "$tmp_current_entries"

if cmp -s "$tmp_entries" "$tmp_current_entries"; then
  echo "No change: NetBird hosts already up to date (${entry_count} entries)"
  exit 0
fi

{
  echo "$BEGIN"
  echo "# Managed by /usr/local/bin/netbird-hosts.sh"
  echo "# Generated at $(date -Is 2>/dev/null || date)"
  cat "$tmp_entries"
  echo "$END"
} > "$tmp_block"

awk -v begin="$BEGIN" -v end="$END" '
  $0 == begin { skip=1; next }
  $0 == end { skip=0; next }
  skip != 1 { print }
' "$HOSTS" > "$tmp_hosts"

printf "\n" >> "$tmp_hosts"
cat "$tmp_block" >> "$tmp_hosts"
printf "\n" >> "$tmp_hosts"

cp -p "$HOSTS" "$BACKUP"
install -o root -g root -m 0644 "$tmp_hosts" "$HOSTS"

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl flush-caches >/dev/null 2>&1 || true
fi

if command -v systemd-resolve >/dev/null 2>&1; then
  systemd-resolve --flush-caches >/dev/null 2>&1 || true
fi

if command -v nscd >/dev/null 2>&1; then
  nscd -i hosts >/dev/null 2>&1 || true
fi

echo "Updated NetBird hosts (${entry_count} entries)"
NETBIRD_HOSTS_RUNTIME

	"${SUDO[@]}" chown root:root "$TARGET_SCRIPT"
	"${SUDO[@]}" chmod 0755 "$TARGET_SCRIPT"
}

install_root_crontab() {
	local tmpdir current stripped newcron
	tmpdir="$(mktemp -d)"
	current="${tmpdir}/root-crontab.current"
	stripped="${tmpdir}/root-crontab.stripped"
	newcron="${tmpdir}/root-crontab.new"

	cleanup_cron_tmp() {
		rm -rf "$tmpdir"
	}
	trap cleanup_cron_tmp RETURN

	if "${SUDO[@]}" crontab -u root -l >"$current" 2>/dev/null; then
		:
	else
		: >"$current"
	fi

	awk -v begin="$CRON_BEGIN" -v end="$CRON_END" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "$current" >"$stripped"

	{
		cat "$stripped"

		if [[ -s "$stripped" ]]; then
			printf "\n"
		fi

		echo "$CRON_BEGIN"
		echo "$CRON_LINE"
		echo "$CRON_END"
	} >"$newcron"

	"${SUDO[@]}" crontab -u root "$newcron"

	echo "Installed root crontab block:"
	echo "$CRON_BEGIN"
	echo "$CRON_LINE"
	echo "$CRON_END"
}

prepare_log_file() {
	"${SUDO[@]}" touch "$LOG_FILE"
	"${SUDO[@]}" chown root:root "$LOG_FILE" || true
	"${SUDO[@]}" chmod 0644 "$LOG_FILE"
}

run_once() {
	if [[ "$RUN_ON_INSTALL" == "1" ]]; then
		echo "Running NetBird hosts update once now..."
		if "${SUDO[@]}" "$TARGET_SCRIPT"; then
			:
		else
			echo "WARNING: First run failed. Check:"
			echo "  ${LOG_FILE}"
			echo "  sudo ${TARGET_SCRIPT}"
		fi
	fi
}

install_deps_if_needed
check_netbird_exists
install_runtime_script
prepare_log_file
install_root_crontab
run_once

echo
echo "Done."
echo "Runtime script: ${TARGET_SCRIPT}"
echo "Log file:       ${LOG_FILE}"
echo
echo "Check cron:"
echo "  sudo crontab -l"
echo
echo "Check log:"
echo "  tail -f ${LOG_FILE}"
