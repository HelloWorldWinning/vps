#!/usr/bin/env bash
set -Eeuo pipefail

FSTAB="/etc/fstab"
MOUNTPOINT="/run"
DEFAULT_SIZE="3G"
TIMEOUT_SECONDS="9"
RESTART_DOCKER=false

# Holds the chosen size after read_target_size runs.
TARGET_SIZE=""

log() {
	printf '[INFO] %s\n' "$*"
}

warn() {
	printf '[WARN] %s\n' "$*" >&2
}

die() {
	printf '[ERROR] %s\n' "$*" >&2
	exit 1
}

require_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "Run as root, for example: sudo $0"
	fi
}

show_current_info() {
	echo
	log "Current /run filesystem:"
	findmnt "$MOUNTPOINT" || true

	echo
	log "Current /run usage:"
	df -h "$MOUNTPOINT"

	echo
	log "Current /run mount options:"
	findmnt -no OPTIONS "$MOUNTPOINT" || true

	echo
	log "Largest direct entries in /run:"
	du -sh /run/* 2>/dev/null | sort -hr | head -n 10 || true
}

validate_size() {
	local size="$1"

	# Accept integers and decimals with optional unit suffix:
	#   3        -> 3G
	#   3G       -> 3G
	#   2.3G     -> 2355M  (converted by normalize_size)
	#   0.5G     -> 512M
	#   3072M    -> 3072M
	#   2.5M     -> 2560K
	#   3145728K -> 3145728K
	#   10%      -> 10%

	# Integer, no unit (bare number -> GB)
	if [[ "$size" =~ ^[0-9]*\.?[0-9]+$ ]]; then
		# Must be > 0
		if awk "BEGIN { exit ($size > 0) ? 0 : 1 }"; then
			return 0
		fi
		return 1
	fi

	# Number with unit suffix K/M/G/T
	if [[ "$size" =~ ^[0-9]*\.?[0-9]+[KkMmGgTt]$ ]]; then
		local num="${size%[KkMmGgTt]}"
		if awk "BEGIN { exit ($num > 0) ? 0 : 1 }"; then
			return 0
		fi
		return 1
	fi

	# Percentage (integer only, kernel doesn't accept decimal %)
	if [[ "$size" =~ ^[1-9][0-9]*%$ ]]; then
		return 0
	fi

	return 1
}

normalize_size() {
	local size="$1"
	local num unit result

	# Percentage — pass through as-is.
	if [[ "$size" =~ %$ ]]; then
		printf '%s\n' "$size"
		return
	fi

	# Bare number (no unit) — treat as GB.
	if [[ "$size" =~ ^[0-9]*\.?[0-9]+$ ]]; then
		num="$size"
		unit="G"
	else
		num="${size%[KkMmGgTt]}"
		unit="${size: -1}"
		unit="$(printf '%s' "$unit" | tr '[:lower:]' '[:upper:]')"
	fi

	# If already an integer, emit directly.
	if [[ "$num" =~ ^[0-9]+$ ]]; then
		printf '%s%s\n' "$num" "$unit"
		return
	fi

	# Decimal — convert down to the next smaller unit as an integer.
	# T -> G, G -> M, M -> K.  K with decimals -> integer K (truncated).
	case "$unit" in
	T)
		result="$(awk "BEGIN { printf \"%d\", $num * 1024 }")"
		printf '%sG\n' "$result"
		;;
	G)
		result="$(awk "BEGIN { printf \"%d\", $num * 1024 }")"
		printf '%sM\n' "$result"
		;;
	M)
		result="$(awk "BEGIN { printf \"%d\", $num * 1024 }")"
		printf '%sK\n' "$result"
		;;
	K)
		result="$(awk "BEGIN { printf \"%d\", $num      }")"
		printf '%sK\n' "$result"
		;;
	*) die "Unsupported unit: $unit" ;;
	esac
}

read_target_size() {
	local input
	local normalized

	# All prompts go to stderr so they are visible even if stdout is captured.
	# Read from /dev/tty so interactive input works inside command substitution
	# or when stdin is redirected.

	echo >&2
	echo "Enter new size for /run tmpfs." >&2
	echo "Examples:" >&2
	echo "  3        means 3G" >&2
	echo "  3G       means 3G" >&2
	echo "  2.3G     means 2355M (auto-converted)" >&2
	echo "  0.5G     means 512M  (auto-converted)" >&2
	echo "  3072M    means 3072M" >&2
	echo "  3145728K means 3145728K" >&2
	echo "  10%      means 10% of RAM" >&2
	echo >&2
	echo "Default: ${DEFAULT_SIZE}. Timeout: ${TIMEOUT_SECONDS}s." >&2
	printf 'New /run size [%s]: ' "$DEFAULT_SIZE" >&2

	if [[ -t 0 ]] || [[ -e /dev/tty ]]; then
		# Try reading from /dev/tty (works inside command substitution).
		if read -r -t "$TIMEOUT_SECONDS" input </dev/tty 2>/dev/null; then
			input="${input:-$DEFAULT_SIZE}"
		else
			echo >&2
			input="$DEFAULT_SIZE"
			log "Input timed out. Using default: $DEFAULT_SIZE"
		fi
	else
		input="$DEFAULT_SIZE"
		log "No terminal available. Using default: $DEFAULT_SIZE"
	fi

	if ! validate_size "$input"; then
		die "Invalid size: '$input'. Use values like 3, 2.3G, 3072M, 0.5G, 3145728K, or 10%."
	fi

	normalized="$(normalize_size "$input")"

	# Store result in global variable instead of relying on stdout capture.
	TARGET_SIZE="$normalized"
}

backup_fstab() {
	local backup="${FSTAB}.bak.$(date +%Y%m%d-%H%M%S)"
	cp -a "$FSTAB" "$backup"
	log "Backed up $FSTAB to $backup"
}

update_fstab_run_entry() {
	local size="$1"
	local tmpfile

	tmpfile="$(mktemp)"

	awk -v size="$size" '
    BEGIN {
        changed = 0
    }

    /^[[:space:]]*#/ || NF == 0 {
        print
        next
    }

    $2 == "/run" && $3 == "tmpfs" {
        opts = $4

        dump = $5
        pass = $6

        if (dump == "") {
            dump = "0"
        }

        if (pass == "") {
            pass = "0"
        }

        n = split(opts, parts, ",")
        newopts = ""

        for (i = 1; i <= n; i++) {
            if (parts[i] !~ /^size=/) {
                if (newopts == "") {
                    newopts = parts[i]
                } else {
                    newopts = newopts "," parts[i]
                }
            }
        }

        if (newopts == "") {
            newopts = "mode=0755,nosuid,nodev,size=" size
        } else {
            newopts = newopts ",size=" size
        }

        if (newopts !~ /(^|,)mode=0755(,|$)/) {
            newopts = newopts ",mode=0755"
        }

        if (newopts !~ /(^|,)nosuid(,|$)/) {
            newopts = newopts ",nosuid"
        }

        if (newopts !~ /(^|,)nodev(,|$)/) {
            newopts = newopts ",nodev"
        }

        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, newopts, dump, pass
        changed = 1
        next
    }

    {
        print
    }

    END {
        if (changed == 0) {
            print "tmpfs\t/run\ttmpfs\tmode=0755,nosuid,nodev,size=" size "\t0\t0"
        }
    }
    ' "$FSTAB" >"$tmpfile"

	# Validate the generated fstab if findmnt supports --verify.
	# Guard against findmnt crashing (segfault = exit code 139).
	if command -v findmnt >/dev/null 2>&1; then
		local verify_rc=0
		findmnt --verify --tab-file "$tmpfile" >/dev/null 2>&1 || verify_rc=$?

		if [[ "$verify_rc" -gt 128 ]]; then
			# findmnt crashed (e.g. segfault 139). Not a real validation failure.
			warn "findmnt --verify crashed (exit $verify_rc); skipping fstab validation."
		elif [[ "$verify_rc" -ne 0 ]]; then
			rm -f "$tmpfile"
			die "Generated fstab failed validation (findmnt exit $verify_rc). No changes applied."
		fi
	else
		warn "findmnt not found; skipping fstab validation."
	fi

	cp "$tmpfile" "$FSTAB"
	rm -f "$tmpfile"

	log "Updated persistent /run tmpfs size in $FSTAB to $size"
}

remount_run() {
	local size="$1"

	if ! mountpoint -q "$MOUNTPOINT"; then
		die "$MOUNTPOINT is not currently a mount point."
	fi

	log "Reloading systemd fstab-generated units..."
	systemctl daemon-reload

	log "Remounting $MOUNTPOINT with size=$size..."
	mount -o "remount,size=${size}" "$MOUNTPOINT"

	echo
	log "New /run status:"
	findmnt "$MOUNTPOINT"
	df -h "$MOUNTPOINT"
}

ask_restart_docker() {
	local answer
	local docker_timeout=5

	echo >&2
	echo "Restart Docker now? This may interrupt running containers." >&2
	echo "Default: yes. Timeout: ${docker_timeout}s." >&2
	printf 'Restart Docker? [Y/n]: ' >&2

	if [[ -t 0 ]] || [[ -e /dev/tty ]]; then
		if read -r -t "$docker_timeout" answer </dev/tty 2>/dev/null; then
			answer="${answer:-Y}"
		else
			echo >&2
			answer="Y"
			log "Docker restart prompt timed out. Defaulting to yes."
		fi
	else
		answer="Y"
		log "No terminal available. Defaulting to yes."
	fi

	case "$answer" in
	n | N | no | NO)
		RESTART_DOCKER=false
		;;
	*)
		RESTART_DOCKER=true
		;;
	esac
}

maybe_restart_docker() {
	if [[ "$RESTART_DOCKER" != true ]]; then
		log "Docker restart skipped."
		return 0
	fi

	if ! command -v systemctl >/dev/null 2>&1; then
		warn "systemctl not found; cannot restart Docker."
		return 0
	fi

	if ! systemctl list-unit-files docker.service >/dev/null 2>&1; then
		warn "docker.service not found; skipping Docker restart."
		return 0
	fi

	log "Restarting Docker..."
	systemctl restart docker

	echo
	log "Docker status:"
	systemctl --no-pager --full status docker | sed -n '1,12p'
}

show_final_state() {
	echo
	log "Persistent /etc/fstab /run entry:"
	grep -E '^[[:space:]]*tmpfs[[:space:]]+/run[[:space:]]+tmpfs' "$FSTAB" || true

	echo
	log "Current /run verification:"
	df -h "$MOUNTPOINT"
	findmnt -no SOURCE,FSTYPE,SIZE,USED,AVAIL,OPTIONS "$MOUNTPOINT" || true

	echo
	log "Verify after reboot with:"
	echo "  df -h /run"
	echo "  findmnt -no SOURCE,FSTYPE,SIZE,USED,AVAIL,OPTIONS /run"
}

main() {
	require_root

	show_current_info

	read_target_size

	echo
	log "Target /run tmpfs size: $TARGET_SIZE"

	backup_fstab
	update_fstab_run_entry "$TARGET_SIZE"
	remount_run "$TARGET_SIZE"

	ask_restart_docker
	maybe_restart_docker

	show_final_state

	echo
	log "Done."
}

main "$@"
