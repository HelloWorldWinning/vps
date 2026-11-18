#!/usr/bin/env bash
# Debian zram installer / manager, v2.0.0
# Run: bash install_zram.sh
# Remote: bash <(curl -fLSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_zram.sh)
# No arguments. First install uses hardware recommendations automatically.
# Existing installations are never retuned, enabled or restarted on entry.
# Recommendations are heuristics, not workload-specific performance guarantees.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
umask 077

VERSION=2.0.0
ZRAM_NO_MENU=${ZRAM_NO_MENU:-0}
CONF=/etc/default/zramswap
SYSCTL=/etc/sysctl.d/90-zram-manager.conf
STATE=/var/lib/zram-manager
BACKUPS=/var/lib/zram-manager/backups
DEV=/dev/zram0
SYS=/sys/block/zram0
TTY_FD=''
TEMP_MASK=0
LAST_BACKUP=''
RAM=0 AVAIL=0 CORES=1 ALGORITHMS='' CURRENT_ALGO=''
LIVE_SIZE=0 LIVE_ORIG=0 LIVE_MEM=0 LIVE_USED=0 LIVE_PRI=0
R_SIZE=0 R_ALGO='' R_PRI=100 R_SW=keep MODE='' REASONS='' CONFIDENCE=''
S_CPU=0 S_STEAL=0 S_IN=0 S_OUT=0 S_MEM=-1 S_CPUP=-1 S_IO=-1 S_FILL=0 S_RATIO=0

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fatal() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}
cleanup() {
	if ((TEMP_MASK)); then
		systemctl unmask --runtime zramswap.service >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "ERROR: line %s failed (exit %s). No automatic retry.\n" "$LINENO" "$?" >&2' ERR

installed() { [[ $(dpkg-query -W -f='${Status}' zram-tools 2>/dev/null || true) == 'install ok installed' ]]; }
active() { awk -v d="$DEV" 'NR>1 && $1==d {f=1} END {exit !f}' /proc/swaps; }
service_active() { systemctl is-active --quiet zramswap.service; }
uint() { [[ $1 =~ ^[0-9]{1,9}$ ]]; }
mib() { awk -v b="${1:-0}" 'BEGIN {printf "%.1f MiB",b/1048576}'; }
ask() {
	local prompt=$1
	REPLY=''
	[[ -n $TTY_FD ]] || return 1
	printf '%s' "$prompt" >&"$TTY_FD"
	IFS= read -r -u "$TTY_FD" REPLY
}
confirm() { ask "$1 [y/N]: " && [[ $REPLY == y || $REPLY == Y ]]; }
pause_menu() { ask 'Press Enter to return...' || true; }
add_reason() { REASONS+="$*"$'\n'; }

# Strict data parser: never source configuration as shell code in this manager.
# Arbitrary shell expressions in an existing config remain untouched until a
# user explicitly replaces it with a generated literal configuration.
setting() {
	local file=$1 key=$2
	[[ -r $file ]] || return 0
	awk -v k="$key" '
      /^[[:space:]]*#/ {next}
      {s=$0; sub(/^[[:space:]]*/,"",s)
       if(s !~ ("^" k "[[:space:]]*=")) next
       sub(/^[^=]*=[[:space:]]*/,"",s); sub(/[[:space:]]+#.*$/,"",s)
       sub(/[[:space:]]*$/,"",s)
       if(s ~ /^"[^"]*"$/ || s ~ /^\047[^\047]*\047$/) s=substr(s,2,length(s)-2)
       v=s}
      END {if(v!="") print v}' "$file"
}
owned_sysctl() { [[ -f $SYSCTL ]] && [[ $(head -n 1 "$SYSCTL") == '# Managed by install_zram.sh (zram-manager)' ]]; }
external_swappiness() {
	local f
	for f in /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf; do
		[[ -f $f && $f != "$SYSCTL" ]] || continue
		if awk '/^[[:space:]]*[-]?[[:space:]]*vm[./]swappiness[[:space:]]*=/ {f=1} END {exit !f}' "$f"; then
			return 0
		fi
	done
	return 1
}
read_hardware() {
	RAM=$(awk '/^MemTotal:/ {printf "%.0f",$2*1024}' /proc/meminfo)
	AVAIL=$(awk '/^MemAvailable:/ {printf "%.0f",$2*1024}' /proc/meminfo)
	[[ -n $AVAIL ]] || AVAIL=$(awk '/^MemFree:/ {printf "%.0f",$2*1024}' /proc/meminfo)
	CORES=$(nproc)
	# cpu.max gives an additional cgroup ceiling; nproc includes affinity.
	local cg path quota period effective
	cg=$(awk -F: '$1=="0" {print $3}' /proc/self/cgroup)
	if [[ -n $cg && $cg != *..* ]]; then
		path="/sys/fs/cgroup${cg%/}"
		while [[ $path == /sys/fs/cgroup* ]]; do
			if [[ -r $path/cpu.max ]]; then
				read -r quota period <"$path/cpu.max"
				if [[ $quota =~ ^[0-9]+$ && $period =~ ^[0-9]+$ ]] && ((period > 0)); then
					effective=$(awk -v q="$quota" -v p="$period" 'BEGIN {printf "%.2f",q/p}')
					CORES=$(awk -v a="$CORES" -v b="$effective" 'BEGIN {print a<b?a:b}')
				fi
			fi
			[[ $path != /sys/fs/cgroup ]] || break
			path=${path%/*}
		done
	fi
	ALGORITHMS=''
	if [[ -r $SYS/comp_algorithm ]]; then
		ALGORITHMS=$(tr -d '[]' <"$SYS/comp_algorithm")
	fi
	read_live
}
read_live() {
	LIVE_SIZE=0 LIVE_ORIG=0 LIVE_MEM=0 LIVE_USED=0 LIVE_PRI=0 CURRENT_ALGO=''
	local compressed extra
	[[ ! -r $SYS/disksize ]] || LIVE_SIZE=$(<"$SYS/disksize")
	if [[ -r $SYS/comp_algorithm ]]; then
		CURRENT_ALGO=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$SYS/comp_algorithm")
	fi
	if [[ -r $SYS/mm_stat ]]; then
		read -r LIVE_ORIG compressed LIVE_MEM extra <"$SYS/mm_stat"
	fi
	if active; then
		read -r LIVE_USED LIVE_PRI < <(awk -v d="$DEV" '$1==d {printf "%.0f %d\n",$4*1024,$5}' /proc/swaps)
	fi
}
has_algo() { [[ $1 =~ ^[a-zA-Z0-9_-]+$ && " $ALGORITHMS " == *" $1 "* ]]; }
ensure_algorithms() {
	if [[ ! -r $SYS/comp_algorithm ]]; then
		modprobe zram || {
			warn 'Kernel cannot load zram (common in restricted containers).'
			return 1
		}
	fi
	[[ -r $SYS/comp_algorithm ]] || {
		warn 'zram0 is unavailable.'
		return 1
	}
	ALGORITHMS=$(tr -d '[]' <"$SYS/comp_algorithm")
}

conflicts() {
	local unit p f bad=0
	for unit in systemd-zram-setup@zram0.service zram-config.service zram-swap.service; do
		if systemctl is-active --quiet "$unit" 2>/dev/null || systemctl is-enabled --quiet "$unit" 2>/dev/null; then
			say "Other manager enabled/active: $unit"
			bad=1
		fi
	done
	for f in /etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf.d/*.conf /usr/lib/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf.d/*.conf; do
		[[ ! -f $f ]] || {
			say "Other zram configuration: $f"
			bad=1
		}
	done
	for p in /sys/block/zram*; do
		[[ -r $p/disksize ]] || continue
		if [[ $p != "$SYS" ]] && (($(<"$p/disksize") > 0)); then
			say "Another initialized zram device: ${p##*/}"
			bad=1
		fi
	done
	if [[ -r $SYS/disksize ]] && (($(<"$SYS/disksize") > 0)); then
		if ! installed || ! service_active; then
			say 'zram0 is initialized, but is not owned by an active zramswap.service.'
			bad=1
		fi
		if findmnt -rn -S "$DEV" 2>/dev/null | awk 'END {exit NR==0}'; then
			say 'zram0 is mounted as a filesystem.'
			bad=1
		fi
	fi
	return "$bad"
}
check_scope() {
	# zram devices are kernel-global. Never size the host's zram using a
	# container's resource limits, even if that container is privileged.
	if systemd-detect-virt --container --quiet 2>/dev/null; then
		warn 'Container detected: zram is kernel-global. Use this manager on the VPS host/KVM guest.'
		return 1
	fi
}
require_managed() {
	check_scope || return 1
	installed || {
		warn 'zram-tools is not installed.'
		return 1
	}
	conflicts || {
		warn 'Management conflict: no configuration or service changes were made.'
		return 1
	}
	[[ ! -L $CONF && ! -L $SYSCTL ]] || {
		warn 'Configuration symlink detected; refusing to replace it.'
		return 1
	}
	if [[ -e $SYSCTL ]] && ! owned_sysctl; then
		warn "$SYSCTL belongs to another configuration; rename it manually before using this manager."
		return 1
	fi
	return 0
}

# Every snapshot contains the two managed files and runtime swappiness.
# Absence is represented explicitly, so restoring does not invent a file.
backup_config() {
	local label=${1:-before-change} dir name src
	dir=$(mktemp -d "$BACKUPS/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX") || return 1
	for name in zramswap manager-sysctl; do
		if [[ $name == zramswap ]]; then src=$CONF; else src=$SYSCTL; fi
		if [[ -f $src ]]; then
			cp -p -- "$src" "$dir/$name" || return 1
		else : >"$dir/$name.absent" || return 1; fi
	done
	cat /proc/sys/vm/swappiness >"$dir/runtime-swappiness" || return 1
	printf '%s\n' "$label" >"$dir/description" || return 1
	LAST_BACKUP=$dir
	say "Backup: $dir"
}
atomic_copy() {
	local src=$1 dest=$2 temp
	mkdir -p -- "${dest%/*}" || return 1
	temp=$(mktemp "${dest%/*}/.zram-manager.XXXXXX") || return 1
	if ! cat -- "$src" >"$temp"; then
		rm -f -- "$temp"
		return 1
	fi
	chmod 644 "$temp" || {
		rm -f -- "$temp"
		return 1
	}
	mv -f -- "$temp" "$dest" || {
		rm -f -- "$temp"
		return 1
	}
}
init_state() {
	[[ ! -L $STATE && ! -L $BACKUPS ]] || fatal 'State directory cannot be a symlink.'
	install -d -m 700 "$STATE" "$BACKUPS"
	if [[ ! -f $STATE/original-swappiness ]]; then
		cat /proc/sys/vm/swappiness >"$STATE/original-swappiness"
	fi
}

hardware_size() {
	local profile=$1 total=$2 size
	if [[ $profile == conservative ]]; then
		size=$((total / 2))
		((size <= 4 * 1024 * 1024 * 1024)) || size=$((4 * 1024 * 1024 * 1024))
	elif ((total <= 2 * 1024 * 1024 * 1024)); then
		size=$total
	elif ((total <= 4 * 1024 * 1024 * 1024)); then
		size=$((2 * 1024 * 1024 * 1024))
	else
		size=$((total / 2))
		((size <= 8 * 1024 * 1024 * 1024)) || size=$((8 * 1024 * 1024 * 1024))
	fi
	# No minimum that could exceed the memory of a tiny VPS.
	printf '%s\n' "$((size / 1048576))"
}
recommended_priority() {
	local max
	max=$(awk 'NR>1 && $1 !~ /\/zram[0-9]+$/ && $5>m {m=$5} END {print m+0}' /proc/swaps)
	if ((max < 100)); then
		R_PRI=100
	elif ((max < 32767)); then
		R_PRI=$((max + 1))
	else
		R_PRI=32767
		add_reason 'Disk swap already uses priority 32767; strict zram precedence is impossible without changing it.'
	fi
}
choose_swappiness() {
	local desired=$1
	R_SW=keep
	if external_swappiness; then
		add_reason 'Existing external swappiness configuration: preserved. No new override is generated.'
	elif owned_sysctl; then
		R_SW=$desired
	elif [[ $(</proc/sys/vm/swappiness) == 60 ]]; then
		R_SW=$desired
	else
		add_reason 'Non-default runtime swappiness: preserved because its origin is unknown.'
	fi
	if [[ $R_SW != keep ]]; then
		add_reason "swappiness=$R_SW is a starting policy, not a proven optimum; it affects all swap devices."
	fi
}
recommend_hardware() {
	local profile=$1 disk
	REASONS='' MODE=$profile CONFIDENCE='hardware baseline; no workload validation'
	R_SIZE=$(hardware_size "$profile" "$RAM")
	if has_algo lz4; then
		R_ALGO=lz4
	elif [[ -n $CURRENT_ALGO ]] && has_algo "$CURRENT_ALGO"; then
		R_ALGO=$CURRENT_ALGO
	else R_ALGO=${ALGORITHMS%% *}; fi
	[[ -n $R_ALGO ]] || {
		warn 'No supported compressor detected.'
		return 1
	}
	recommended_priority
	disk=$(awk 'NR>1 && $1 !~ /\/zram[0-9]+$/ {n++} END {print n+0}' /proc/swaps)
	if [[ $profile == conservative ]]; then
		choose_swappiness 60
		add_reason 'Conservative: logical size = 50% RAM, capped at 4 GiB; speed-first compression.'
	else
		if ((disk)); then choose_swappiness 60; else choose_swappiness 100; fi
		add_reason 'Hardware: <=2 GiB RAM: 100%; 2-4 GiB: 2 GiB; larger: 50%, capped at 8 GiB.'
	fi
	add_reason 'No disk benchmark, swapfile creation, writeback or unrelated VM tuning.'
	if [[ -r /sys/module/zswap/parameters/enabled ]] && [[ $(</sys/module/zswap/parameters/enabled) == Y ]]; then
		add_reason 'zswap is enabled: it is reported but not automatically disabled or reconfigured.'
	fi
}

pressure_total() {
	local file=$1 kind=$2
	if [[ -r $file ]]; then
		awk -v k="$kind" '$1==k {for(i=2;i<=NF;i++) if($i ~ /^total=/) {sub(/^total=/,"",$i);print $i;found=1}} END {if(!found)print -1}' "$file"
	else printf '%s\n' -1; fi
}
cpu_snapshot() { awk '/^cpu / {s=0;for(i=2;i<=9;i++)s+=$i;print s,$5+$6,$9;exit}' /proc/stat; }
vm_snapshot() { awk '$1=="pswpin" {i=$2} $1=="pswpout" {o=$2} END {print i+0,o+0}' /proc/vmstat; }
psi_delta() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN {if(a<0||b<a)print -1;else printf "%.2f",(b-a)/(t*10000)}'; }
sample_runtime() {
	local t1 idle1 steal1 t2 idle2 steal2 in1 out1 in2 out2 m1 c1 io1 m2 c2 io2 start end elapsed pagesize
	say 'Sampling CPU, PSI and swap activity for 10 seconds (no stress test)...'
	read -r t1 idle1 steal1 < <(cpu_snapshot)
	read -r in1 out1 < <(vm_snapshot)
	m1=$(pressure_total /proc/pressure/memory some)
	c1=$(pressure_total /proc/pressure/cpu some)
	io1=$(pressure_total /proc/pressure/io some)
	start=$(awk '{print $1}' /proc/uptime)
	sleep 10
	end=$(awk '{print $1}' /proc/uptime)
	elapsed=$(awk -v a="$start" -v b="$end" 'BEGIN {print b>a?b-a:10}')
	read -r t2 idle2 steal2 < <(cpu_snapshot)
	read -r in2 out2 < <(vm_snapshot)
	m2=$(pressure_total /proc/pressure/memory some)
	c2=$(pressure_total /proc/pressure/cpu some)
	io2=$(pressure_total /proc/pressure/io some)
	S_CPU=$(awk -v t="$((t2 - t1))" -v i="$((idle2 - idle1))" -v s="$((steal2 - steal1))" 'BEGIN {if(t>0)printf "%.2f",100*(t-i-s)/t;else print 0}')
	S_STEAL=$(awk -v t="$((t2 - t1))" -v s="$((steal2 - steal1))" 'BEGIN {if(t>0)printf "%.2f",100*s/t;else print 0}')
	pagesize=$(getconf PAGESIZE)
	S_IN=$(awk -v n="$((in2 - in1))" -v p="$pagesize" -v t="$elapsed" 'BEGIN {printf "%.3f",n*p/t/1048576}')
	S_OUT=$(awk -v n="$((out2 - out1))" -v p="$pagesize" -v t="$elapsed" 'BEGIN {printf "%.3f",n*p/t/1048576}')
	S_MEM=$(psi_delta "$m1" "$m2" "$elapsed")
	S_CPUP=$(psi_delta "$c1" "$c2" "$elapsed")
	S_IO=$(psi_delta "$io1" "$io2" "$elapsed")
	read_hardware
	S_FILL=$(awk -v u="$LIVE_USED" -v d="$LIVE_SIZE" 'BEGIN {if(d>0)printf "%.2f",100*u/d;else print 0}')
	S_RATIO=$(awk -v u="$LIVE_ORIG" -v m="$LIVE_MEM" 'BEGIN {if(m>0)printf "%.2f",u/m;else print 0}')
}
# Conservative single-window rules; load is not proof that zram caused it.
# A history log is an audit trail, NOT a replacement for continuous monitoring.
runtime_decision() {
	local maxsize oldsize usedmib
	if ! active || ((LIVE_ORIG < 64 * 1048576)); then
		CONFIDENCE='insufficient zram data; hardware fallback shown, current configuration not auto-replaced'
		add_reason 'Less than 64 MiB representative zram data, or device inactive: compression evidence is insufficient.'
		return 0
	fi
	CONFIDENCE='limited: 10-second observation, not an all-day optimum'
	oldsize=$((LIVE_SIZE / 1048576))
	R_SIZE=$oldsize R_ALGO=$CURRENT_ALGO R_PRI=$LIVE_PRI R_SW=keep
	add_reason 'Runtime mode starts from the live device, and preserves swappiness and compressor without a controlled A/B test.'
	maxsize=$((RAM / 1048576))
	((maxsize <= 16384)) || maxsize=16384
	usedmib=$(((LIVE_USED + 1048575) / 1048576))
	if awk -v f="$S_FILL" -v q="$S_RATIO" -v m="$S_MEM" -v c="$S_CPU" -v p="$S_CPUP" -v s="$S_STEAL" -v a="$AVAIL" -v r="$RAM" -v z="$LIVE_MEM" 'BEGIN {exit !(f>=80 && q>=2 && m>=1 && m<10 && c<70 && p>=0 && p<10 && s<10 && a>r*.1 && z<r*.3)}'; then
		R_SIZE=$((oldsize + oldsize / 4))
		((R_SIZE <= maxsize)) || R_SIZE=$maxsize
		((R_SIZE >= oldsize)) || R_SIZE=$oldsize
		if ((R_SIZE > oldsize)); then
			add_reason 'Candidate +25% capacity: >=80% full, effective ratio >=2, memory pressure present, CPU and RAM headroom available.'
		else add_reason 'Capacity is already at the automatic growth ceiling; keep it.'; fi
	elif awk -v q="$S_RATIO" -v z="$LIVE_MEM" -v r="$RAM" -v m="$S_MEM" 'BEGIN {exit !(q<1.3 && z>r*.3 && m<1 && m>=0)}'; then
		# Leave at least 25% room above allocated swap slots. A resize is
		# deferred unless the separate swapoff memory preflight succeeds.
		R_SIZE=$((oldsize * 3 / 4))
		((R_SIZE >= usedmib + usedmib / 4 + 1)) || R_SIZE=$((usedmib + usedmib / 4 + 1))
		((R_SIZE <= oldsize)) || R_SIZE=$oldsize
		add_reason 'Low compression benefit and >30% RAM consumed: reduce unused capacity by at most 25%, retaining room above current usage.'
	else
		add_reason 'No sufficient evidence for a capacity change: keep the live size.'
	fi
	if awk -v i="$S_IN" -v o="$S_OUT" -v m="$S_MEM" 'BEGIN {exit !(i>1 && o>1 && m>=1)}'; then
		add_reason 'Frequent bidirectional swap activity: possible working-set thrashing; extra zram alone may not help.'
	fi
	if awk -v c="$S_CPU" -v p="$S_CPUP" -v s="$S_STEAL" 'BEGIN {exit !(c>=70||p>=10||s>=10)}'; then
		add_reason 'CPU contention observed; this does not establish compressor causality. No automatic algorithm switch.'
	fi
	recommended_priority
}

load_saved() {
	local percent size algo pri
	algo=$(setting "$CONF" ALGO)
	pri=$(setting "$CONF" PRIORITY)
	percent=$(setting "$CONF" PERCENT)
	size=$(setting "$CONF" SIZE)
	[[ -n $algo ]] || algo=lz4
	[[ -n $pri ]] || pri=100
	[[ -n $size ]] || size=512
	if [[ -n $percent ]]; then
		uint "$percent" && ((10#$percent > 0 && 10#$percent <= 1000)) || {
			warn 'Cannot interpret PERCENT as a literal integer.'
			return 1
		}
		SAVED_BYTES=$((RAM * 10#$percent / 100))
	else
		uint "$size" && ((10#$size > 0 && 10#$size <= 1048576)) || {
			warn 'Cannot interpret SIZE as a literal MiB integer.'
			return 1
		}
		SAVED_BYTES=$((10#$size * 1048576))
	fi
	[[ $algo =~ ^[a-zA-Z0-9_-]+$ && $pri =~ ^-?[0-9]{1,5}$ ]] || {
		warn 'Cannot interpret algorithm/priority; use a generated configuration.'
		return 1
	}
	SAVED_ALGO=$algo
	if [[ $pri == -* ]]; then SAVED_PRI=$((-10#${pri#-})); else SAVED_PRI=$((10#$pri)); fi
	((SAVED_PRI >= -1 && SAVED_PRI <= 32767)) || {
		warn 'Invalid saved priority.'
		return 1
	}
}
saved_swappiness() {
	local s
	if owned_sysctl; then
		s=$(awk -F= '/^vm.swappiness=/ {print $2}' "$SYSCTL")
		if uint "$s" && ((10#$s <= 200)); then printf '%s\n' "$((10#$s))"; else return 1; fi
	else printf '%s\n' keep; fi
}
show_proposal() {
	say ''
	say "Mode: $MODE | Evidence: $CONFIDENCE"
	printf '%-20s %-24s %-24s\n' 'Parameter' 'Live' 'Proposed'
	printf '%-20s %-24s %-24s\n' 'Logical size' "$(mib "$LIVE_SIZE")" "$R_SIZE MiB"
	printf '%-20s %-24s %-24s\n' 'Compressor' "${CURRENT_ALGO:-inactive}" "$R_ALGO"
	printf '%-20s %-24s %-24s\n' 'Swap priority' "$LIVE_PRI" "$R_PRI"
	printf '%-20s %-24s %-24s\n' 'swappiness' "$(</proc/sys/vm/swappiness)" "$R_SW"
	say 'Saved configuration before change:'
	if [[ -r $CONF ]]; then awk '/^[[:space:]]*[^#[:space:]]/ {print "  "$0}' "$CONF"; else say '  none'; fi
	printf '%s' "$REASONS"
}
write_recommendation() {
	local work swchanged=0 same=0
	work=$(mktemp -d "$STATE/.proposal.XXXXXX")
	cat >"$work/zramswap" <<EOF
# Managed by install_zram.sh (zram-manager)
# Version: $VERSION | Policy: $MODE
# Logical uncompressed capacity; physical memory is allocated on demand.
ALGO=$R_ALGO
SIZE=$R_SIZE
PRIORITY=$R_PRI
EOF
	if [[ $R_SW != keep ]]; then
		printf '# Managed by install_zram.sh (zram-manager)\nvm.swappiness=%s\n' "$R_SW" >"$work/sysctl"
		cmp -s "$work/sysctl" "$SYSCTL" || swchanged=1
	fi
	if load_saved && ((SAVED_BYTES == R_SIZE * 1048576 && SAVED_PRI == R_PRI)) && [[ $SAVED_ALGO == "$R_ALGO" ]] && ((!swchanged)); then same=1; fi
	if ((same)); then
		say 'Saved parameter values are unchanged; no backup or config rewrite needed.'
	else
		backup_config "before-$MODE"
		atomic_copy "$work/zramswap" "$CONF"
		if [[ $R_SW != keep ]]; then atomic_copy "$work/sysctl" "$SYSCTL"; fi
		say 'Configuration saved persistently.'
	fi
	{
		printf '\n=== %s | %s | %s ===\n' "$(date -u +%FT%TZ)" "$MODE" "$CONFIDENCE"
		printf 'RAM=%s CPU=%s size_MiB=%s algo=%s priority=%s swappiness=%s\n' "$RAM" "$CORES" "$R_SIZE" "$R_ALGO" "$R_PRI" "$R_SW"
		printf 'CPU_busy=%s steal=%s PSI_mem=%s PSI_cpu=%s PSI_io=%s swapin_MiB_s=%s swapout_MiB_s=%s ratio=%s fill_pct=%s\n' "$S_CPU" "$S_STEAL" "$S_MEM" "$S_CPUP" "$S_IO" "$S_IN" "$S_OUT" "$S_RATIO" "$S_FILL"
		printf '%s' "$REASONS"
	} >>"$STATE/recommendations.log"
	# Bound the audit trail; it is not a background collector.
	tail -n 2000 "$STATE/recommendations.log" >"$work/log"
	install -m 600 "$work/log" "$STATE/recommendations.log"
	rm -rf -- "$work"
}

# Conservatively demand enough available RAM to fault all used swap pages
# back in plus headroom; do not count other swap as guaranteed capacity.
preflight_stop() {
	local used reserve need
	active || return 0
	read_hardware
	used=$LIVE_ORIG
	((used >= LIVE_USED)) || used=$LIVE_USED
	((used > 0)) || return 0
	reserve=$((RAM / 10))
	((reserve >= 128 * 1048576)) || reserve=$((128 * 1048576))
	need=$((used + used / 5 + reserve))
	if ((AVAIL < need)); then
		warn "Stop/restart deferred: available $(mib "$AVAIL"), conservative requirement $(mib "$need")."
		say 'Saved settings remain available for the next service start or reboot.'
		return 1
	fi
	say 'Memory preflight passed; concurrent workload changes can still affect swapoff.'
}
verify_live() {
	read_hardware
	load_saved || return 1
	active && service_active || {
		warn 'zram swap/service is not active.'
		return 1
	}
	if ((LIVE_SIZE != SAVED_BYTES || LIVE_PRI != SAVED_PRI)) || [[ $CURRENT_ALGO != "$SAVED_ALGO" ]]; then
		warn 'Live size, compressor or swap priority does not match saved configuration.'
		return 1
	fi
	return 0
}
apply_swappiness() {
	local s
	s=$(saved_swappiness) || {
		warn 'Invalid manager swappiness file.'
		return 1
	}
	[[ $s != keep ]] || return 0
	sysctl -q -w "vm.swappiness=$s" || return 1
	[[ $(</proc/sys/vm/swappiness) == "$s" ]]
}
stop_service() {
	preflight_stop || return 1
	systemctl stop zramswap.service || {
		warn 'Service stop failed; inspect logs.'
		return 1
	}
	if active; then
		warn 'Swap is still active; aborting.'
		return 1
	fi
	if [[ -r $SYS/disksize ]] && (($(<"$SYS/disksize") > 0)); then
		warn 'Device remains initialized after stop; aborting without resetting it.'
		return 1
	fi
}
apply_saved() {
	local rollback prior_sw was_active=0 size algo pri
	require_managed || return 1
	read_hardware
	load_saved || return 1
	ensure_algorithms || return 1
	has_algo "$SAVED_ALGO" || {
		warn "Saved algorithm is unavailable: $SAVED_ALGO"
		return 1
	}
	if verify_live >/dev/null 2>&1; then
		apply_swappiness || return 1
		say 'Saved configuration already matches the running device.'
		return 0
	fi
	rollback=$(mktemp -d "$STATE/.apply.XXXXXX") || return 1
	prior_sw=$(</proc/sys/vm/swappiness)
	cp -p -- "$CONF" "$rollback/desired" || {
		warn 'Could not save the desired config before restart; no service changes made.'
		rm -rf -- "$rollback"
		return 1
	}
	if active; then
		was_active=1
		size=$((LIVE_SIZE / 1048576))
		algo=$CURRENT_ALGO
		pri=$LIVE_PRI
		printf 'ALGO=%s\nSIZE=%s\nPRIORITY=%s\n' "$algo" "$size" "$pri" >"$rollback/live" || {
			rm -rf -- "$rollback"
			return 1
		}
		if ! stop_service; then
			rm -rf -- "$rollback"
			return 1
		fi
	elif service_active; then
		if ! stop_service; then
			rm -rf -- "$rollback"
			return 1
		fi
	fi
	if systemctl start zramswap.service && verify_live && apply_swappiness; then
		say 'Applied and verified. Boot enablement was left unchanged.'
		rm -rf -- "$rollback"
		return 0
	fi
	warn 'Apply failed; saved configuration remains pending. Attempting to restore the previous running device.'
	journalctl -u zramswap.service -n 25 --no-pager || true
	# Only stop the failed attempt if ownership and memory preflight still pass.
	if conflicts && stop_service; then
		if ((was_active)); then
			atomic_copy "$rollback/live" "$CONF" || {
				warn "Rollback file write failed. Recovery files: $rollback"
				return 1
			}
			systemctl reset-failed zramswap.service || true
			if systemctl start zramswap.service && active; then say 'Previous live device restored.'; else warn 'Rollback start failed; inspect the service log.'; fi
			atomic_copy "$rollback/desired" "$CONF" || {
				warn "Could not restore desired config. Recovery files: $rollback"
				return 1
			}
		fi
	else warn 'Could not safely stop the failed device; no reset attempted.'; fi
	sysctl -q -w "vm.swappiness=$prior_sw" || true
	rm -rf -- "$rollback"
	return 1
}
offer_apply() {
	say '1 Apply saved settings now (memory preflight)'
	say '2 Leave saved settings for the next service start / reboot'
	if ask 'Choice [2]: ' && [[ $REPLY == 1 ]]; then
		apply_saved || warn 'Not applied. Check status / diagnostics; saved configuration is retained.'
	else say 'Saved for next start. A disabled service must be enabled separately to start at boot.'; fi
}

show_status() {
	read_hardware
	say ''
	say "========== zram manager $VERSION =========="
	printf 'RAM: %s | Available: %s | Effective CPU ceiling: %s\n' "$(mib "$RAM")" "$(mib "$AVAIL")" "$CORES"
	printf 'OS: %s | Kernel: %s | Virtualization: %s\n' "${PRETTY_NAME:-Debian}" "$(uname -r)" "$(systemd-detect-virt 2>/dev/null || true)"
	if installed; then say 'zram-tools: installed'; else say 'zram-tools: not installed'; fi
	printf 'Service: %s | Boot: %s\n' "$(systemctl is-active zramswap.service 2>/dev/null || true)" "$(systemctl is-enabled zramswap.service 2>/dev/null || true)"
	free -h || true
	say ''
	say 'Active swap:'
	swapon --show --bytes || cat /proc/swaps
	say ''
	say 'zram:'
	if command -v zramctl >/dev/null; then zramctl || true; fi
	if ((LIVE_ORIG > 0)); then
		printf 'Original data: %s | Actual RAM including overhead: %s\n' "$(mib "$LIVE_ORIG")" "$(mib "$LIVE_MEM")"
		awk -v u="$LIVE_ORIG" -v m="$LIVE_MEM" 'BEGIN {if(m>0)printf "Effective ratio: %.2fx | Net memory saved: %.1f MiB\n",u/m,(u-m)/1048576}'
	fi
	printf 'Current swappiness: %s\n' "$(</proc/sys/vm/swappiness)"
	if [[ -r /sys/module/zswap/parameters/enabled ]]; then printf 'zswap enabled: %s\n' "$(</sys/module/zswap/parameters/enabled)"; fi
	say 'Saved configuration:'
	if [[ -r $CONF ]]; then cat "$CONF"; else say '(none)'; fi
	if owned_sysctl; then cat "$SYSCTL"; fi
	if active; then
		if verify_live >/dev/null 2>&1; then
			if [[ $(saved_swappiness || true) == keep || $(saved_swappiness || true) == "$(</proc/sys/vm/swappiness)" ]]; then
				say 'Saved settings match the live device.'
			else say 'Pending: saved swappiness differs from runtime.'; fi
		else say 'Pending/different: saved settings do not match the live device.'; fi
	else say 'Device inactive. Saved settings will be read on the next service start.'; fi
	say 'PSI (- if unsupported):'
	local p
	for p in memory cpu io; do [[ ! -r /proc/pressure/$p ]] || {
		printf '%s: ' "$p"
		head -n 1 "/proc/pressure/$p"
	}; done
	say '============================================'
}

configure_mode() {
	local profile=$1
	require_managed || return 0
	read_hardware
	ensure_algorithms || return 0
	if [[ $profile == runtime ]]; then
		recommend_hardware hardware || return 0
		MODE=runtime
		sample_runtime
		runtime_decision
		printf 'Observed: CPU=%s%% steal=%s%% memory_PSI=%s%% CPU_PSI=%s%% swap_in=%s MiB/s swap_out=%s MiB/s\n' "$S_CPU" "$S_STEAL" "$S_MEM" "$S_CPUP" "$S_IN" "$S_OUT"
	else recommend_hardware "$profile" || return 0; fi
	show_proposal
	if [[ $profile == runtime && $CONFIDENCE == insufficient* ]]; then
		say 'Hardware fallback is displayed only. Use option 2 to save a hardware recommendation.'
		return 0
	fi
	confirm 'Save these settings persistently?' || {
		say 'Cancelled.'
		return 0
	}
	write_recommendation
	offer_apply
}
custom_config() {
	require_managed || return 0
	read_hardware
	ensure_algorithms || return 0
	recommend_hardware hardware || return 0
	MODE=custom CONFIDENCE='manual settings'
	local size algo pri sw
	ask "Logical size in MiB [$R_SIZE], maximum $((RAM * 2 / 1048576)): " || return 0
	size=${REPLY:-$R_SIZE}
	uint "$size" && ((10#$size >= 16 && 10#$size <= RAM * 2 / 1048576)) || {
		warn 'Size must be >=16 MiB and <=2x RAM.'
		return 0
	}
	say "Supported algorithms: $ALGORITHMS"
	ask "Compressor [$R_ALGO]: " || return 0
	algo=${REPLY:-$R_ALGO}
	has_algo "$algo" || {
		warn 'Unsupported algorithm.'
		return 0
	}
	ask "Swap priority 0..32767 [$R_PRI]: " || return 0
	pri=${REPLY:-$R_PRI}
	uint "$pri" && ((10#$pri <= 32767)) || {
		warn 'Invalid priority.'
		return 0
	}
	ask 'swappiness 0..200, or keep [keep]: ' || return 0
	sw=${REPLY:-keep}
	if [[ $sw != keep ]]; then
		uint "$sw" && ((10#$sw <= 200)) || {
			warn 'Invalid swappiness.'
			return 0
		}
		sw=$((10#$sw))
		if external_swappiness; then
			warn 'Another sysctl file defines swappiness. Resolve it manually; this manager will not add a competing override.'
			return 0
		fi
	fi
	R_SIZE=$((10#$size)) R_ALGO=$algo R_PRI=$((10#$pri)) R_SW=$sw
	REASONS='Manual settings; keep means leave the existing swappiness configuration unchanged.'$'\n'
	show_proposal
	confirm 'Save these settings persistently?' || return 0
	write_recommendation
	offer_apply
}
service_menu() {
	local choice
	while :; do
		say ''
		say '1 Start | 2 Stop | 3 Enable at boot | 4 Disable at boot | 5 Apply saved config | 0 Back'
		ask 'Service choice: ' || return 0
		choice=$REPLY
		[[ $choice != 0 ]] || return 0
		require_managed || return 0
		case $choice in
		1) apply_saved || warn 'Start/apply failed or deferred.' ;;
		2) if confirm 'Stop zram now? Boot setting stays unchanged.'; then stop_service || warn 'Stop failed or deferred.'; fi ;;
		3) systemctl enable zramswap.service || warn 'Could not enable service.' ;;
		4) systemctl disable zramswap.service || warn 'Could not disable service.' ;;
		5) apply_saved || warn 'Apply failed or deferred.' ;;
		*) say 'Unknown choice.' ;;
		esac
	done
}

restore_snapshot() {
	local dir=$1 name dest
	[[ -d $dir && -f $dir/runtime-swappiness ]] || {
		warn 'Invalid backup.'
		return 1
	}
	for name in zramswap manager-sysctl; do
		[[ -f $dir/$name || -f $dir/$name.absent ]] || {
			warn "Incomplete backup: $name"
			return 1
		}
	done
	backup_config before-restore || return 1
	for name in zramswap manager-sysctl; do
		if [[ $name == zramswap ]]; then dest=$CONF; else dest=$SYSCTL; fi
		if [[ -f $dir/$name ]]; then
			atomic_copy "$dir/$name" "$dest" || return 1
		elif [[ -f $dir/$name.absent ]]; then
			rm -f -- "$dest" || return 1
		else
			warn "Incomplete backup: $name"
			return 1
		fi
	done
	# If no old sysctl file existed, create a manager override for the captured
	# runtime value only when there is no competing explicit external policy.
	if ! [[ -f $SYSCTL ]] && ! external_swappiness; then
		local v
		v=$(<"$dir/runtime-swappiness")
		if uint "$v" && ((10#$v <= 200)); then
			printf '# Managed by install_zram.sh (zram-manager)\nvm.swappiness=%s\n' "$v" >"$dir/.restore-sysctl"
			atomic_copy "$dir/.restore-sysctl" "$SYSCTL"
			rm -f "$dir/.restore-sysctl"
		fi
	fi
	say 'Backup restored to disk. Service enablement was not changed.'
}
restore_package_defaults() {
	local work deb path v
	work=$(mktemp -d "$STATE/.defaults.XXXXXX") || return 1
	say 'Downloading the installed package version to extract its real default configuration...'
	v=$(dpkg-query -W -f='${Version}' zram-tools)
	if ! (cd "$work" && apt-get download "zram-tools=$v"); then
		rm -rf "$work"
		warn 'Installed version is unavailable in configured repositories; no settings changed.'
		return 1
	fi
	deb=''
	for path in "$work"/*.deb; do [[ ! -f $path ]] || deb=$path; done
	if [[ -z $deb ]] || ! dpkg-deb -x "$deb" "$work/unpacked" || [[ ! -f $work/unpacked/etc/default/zramswap ]]; then
		rm -rf "$work"
		warn 'Could not extract package defaults.'
		return 1
	fi
	backup_config before-package-defaults || return 1
	atomic_copy "$work/unpacked/etc/default/zramswap" "$CONF" || return 1
	if owned_sysctl; then
		rm -f -- "$SYSCTL"
		say 'Manager swappiness override removed. The existing runtime value is unchanged until explicitly restored or rebooted.'
	fi
	rm -rf "$work"
	say 'Exact package default configuration restored to disk.'
}
backup_menu() {
	local choice dir i
	local -a dirs=()
	require_managed || return 0
	say '1 Create backup | 2 Restore backup | 3 Restore Debian package defaults | 0 Back'
	ask 'Choice: ' || return 0
	choice=$REPLY
	case $choice in
	1) backup_config manual ;;
	2)
		while IFS= read -r dir; do dirs+=("$dir"); done < <(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d | sort -r)
		((${#dirs[@]})) || {
			say 'No backups.'
			return 0
		}
		i=0
		for dir in "${dirs[@]}"; do
			i=$((i + 1))
			printf '%d %s (%s)\n' "$i" "${dir##*/}" "$(cat "$dir/description" 2>/dev/null || true)"
		done
		ask 'Backup number (0 cancels): ' || return 0
		uint "$REPLY" || return 0
		i=$((10#$REPLY))
		((i >= 1 && i <= ${#dirs[@]})) || return 0
		confirm 'Restore this backup to disk?' || return 0
		restore_snapshot "${dirs[i - 1]}" || return 0
		offer_apply
		;;
	3)
		confirm 'Restore package defaults? Runtime swappiness is left unchanged.' || return 0
		restore_package_defaults || return 0
		offer_apply
		;;
	esac
}
diagnostics() {
	say '--- service ---'
	systemctl --no-pager --full status zramswap.service || true
	say '--- recent service journal ---'
	journalctl -u zramswap.service -n 50 --no-pager || true
	say '--- conflicts ---'
	if conflicts; then say 'No known conflict detected.'; fi
	say '--- saved vs live ---'
	if installed && verify_live; then say 'Device settings verified.'; fi
	say '--- memory / swap backing storage ---'
	df -hT / || true
	lsblk -o NAME,TYPE,SIZE,ROTA,FSTYPE,MOUNTPOINTS 2>/dev/null || lsblk || true
	say 'Disk properties inside a VPS may not represent physical storage performance.'
	say '--- zram I/O errors and memory statistics ---'
	local f
	for f in io_stat mm_stat backing_dev mem_limit; do [[ ! -r $SYS/$f ]] || {
		printf '%s: ' "$f"
		cat "$SYS/$f"
	}; done
	say '--- swappiness definitions ---'
	local p
	for p in /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf; do
		[[ ! -f $p ]] || awk -v f="$p" '/^[[:space:]]*[-]?[[:space:]]*vm[./]swappiness[[:space:]]*=/ {print f ": " $0}' "$p"
	done
	say '--- last recommendations ---'
	[[ ! -f $STATE/recommendations.log ]] || tail -n 45 "$STATE/recommendations.log"
}
uninstall_manager() {
	local original
	require_managed || return 0
	say 'This removes zram-tools and the manager-owned configuration, preserving disk swap and backups.'
	ask 'Type UNINSTALL to continue: ' || return 0
	[[ $REPLY == UNINSTALL ]] || {
		say 'Cancelled.'
		return 0
	}
	backup_config before-uninstall
	stop_service || {
		warn 'Uninstall cancelled because stopping was unsafe or unsuccessful.'
		return 0
	}
	systemctl disable zramswap.service || return 1
	# remove (not purge): retain non-manager package conffiles and all dependencies.
	if ! env DEBIAN_FRONTEND=noninteractive apt-get remove -y zram-tools; then
		warn 'Package removal failed. Configuration and backups were retained.'
		return 1
	fi
	if owned_sysctl; then
		rm -f -- "$SYSCTL"
		if ! external_swappiness && [[ -r $STATE/original-swappiness ]]; then
			original=$(<"$STATE/original-swappiness")
			if uint "$original" && ((10#$original <= 200)); then sysctl -q -w "vm.swappiness=$original" || true; fi
		fi
	fi
	if [[ -f $CONF ]] && [[ $(head -n 1 "$CONF") == '# Managed by install_zram.sh (zram-manager)' ]]; then rm -f -- "$CONF"; fi
	say "Uninstalled. Backups retained at $BACKUPS. Exiting prevents immediate automatic reinstallation."
	exit 0
}

first_install() {
	local was_masked
	check_scope || fatal 'Automatic installation in containers is unsupported.'
	conflicts || fatal 'Existing zram manager/device detected. Resolve ownership before automatic installation.'
	[[ ! -L $CONF && ! -L $SYSCTL ]] || fatal 'Refusing to replace symlinked configuration.'
	[[ ! -e $SYSCTL ]] || owned_sysctl || fatal 'Manager sysctl path is occupied by an unrelated file.'
	was_masked=$(systemctl is-enabled zramswap.service 2>/dev/null || true)
	[[ $was_masked != masked && $was_masked != masked-runtime ]] || fatal 'zramswap.service is explicitly masked; unmask it manually before installing.'
	say 'First installation: hardware recommendation will be generated, saved and enabled automatically.'
	# Runtime mask prevents package postinst from starting with package defaults
	# before the detected hardware configuration has been written.
	systemctl mask --runtime zramswap.service
	TEMP_MASK=1
	apt-get update
	env DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold zram-tools util-linux kmod procps
	ensure_algorithms || fatal 'zram unavailable. Package remains installed; inspect kernel/container support.'
	read_hardware
	recommend_hardware hardware || fatal 'Could not generate hardware recommendation.'
	MODE=hardware
	show_proposal
	write_recommendation
	systemctl unmask --runtime zramswap.service
	TEMP_MASK=0
	systemctl daemon-reload
	systemctl enable zramswap.service
	systemctl is-enabled --quiet zramswap.service || fatal 'Boot enablement verification failed.'
	if ! apply_saved; then fatal 'Installed but activation failed. Saved settings and diagnostics are retained.'; fi
	say 'Installed: hardware recommendation is saved, active, verified and enabled at boot.'
}
main_menu() {
	while :; do
		cat <<'MENU'

1  Status / saved and live configuration
2  Hardware recommendation
3  Hardware + current runtime optimization (10-second sample)
4  Hardware conservative configuration
5  Custom configuration
6  Service / boot / apply saved settings
7  Backups / restore / Debian package defaults
8  Logs / diagnostics
9  Uninstall
0  Exit
MENU
		ask 'Choice: ' || {
			say 'Input ended. Exiting without further changes.'
			return 0
		}
		case $REPLY in
		1) show_status ;;
		2) configure_mode hardware ;;
		3) configure_mode runtime ;;
		4) configure_mode conservative ;;
		5) custom_config ;;
		6) service_menu ;;
		7) backup_menu ;;
		8) diagnostics ;;
		9) uninstall_manager ;;
		0 | '') return 0 ;;
		*) say 'Unknown choice.' ;;
		esac
		pause_menu
	done
}
root_payload() {
	# A process-substitution source is a pipe that has already been consumed.
	# Serialize only this script's named functions and non-secret variables;
	# never reopen /dev/fd/63, forward arbitrary environment functions or refetch.
	local -a names=(say warn fatal cleanup installed active service_active uint mib
		ask confirm pause_menu add_reason setting owned_sysctl external_swappiness
		read_hardware read_live has_algo ensure_algorithms conflicts check_scope
		require_managed backup_config atomic_copy init_state hardware_size
		recommended_priority choose_swappiness recommend_hardware pressure_total
		cpu_snapshot vm_snapshot psi_delta sample_runtime runtime_decision load_saved
		saved_swappiness show_proposal write_recommendation preflight_stop verify_live
		apply_swappiness stop_service apply_saved offer_apply show_status configure_mode
		custom_config service_menu restore_snapshot restore_package_defaults backup_menu
		diagnostics uninstall_manager first_install main_menu root_payload main)
	printf '%s\n' 'set -Eeuo pipefail' 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' 'export LC_ALL=C' 'umask 077'
	declare -p ZRAM_NO_MENU VERSION CONF SYSCTL STATE BACKUPS DEV SYS TTY_FD TEMP_MASK LAST_BACKUP \
		RAM AVAIL CORES ALGORITHMS CURRENT_ALGO LIVE_SIZE LIVE_ORIG LIVE_MEM LIVE_USED LIVE_PRI \
		R_SIZE R_ALGO R_PRI R_SW MODE REASONS CONFIDENCE S_CPU S_STEAL S_IN S_OUT S_MEM S_CPUP S_IO S_FILL S_RATIO
	declare -f "${names[@]}"
	cat <<'ROOT_ENTRY'
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "ERROR: line %s failed (exit %s).\n" "$LINENO" "$?" >&2' ERR
main
ROOT_ENTRY
}
main() {
	(($# == 0)) || fatal 'No arguments needed: bash install_zram.sh'
	if ((EUID != 0)); then
		command -v sudo >/dev/null || fatal 'Run as root; sudo is unavailable.'
		say 'Requesting root privileges...'
		sudo -v
		root_payload | sudo bash -s
		return
	fi
	[[ -r /etc/os-release ]] || fatal 'Cannot identify OS.'
	. /etc/os-release
	[[ ${ID:-} == debian ]] || fatal 'This script supports Debian only.'
	[[ -d /run/systemd/system ]] || fatal 'systemd is required.'
	command -v flock >/dev/null || fatal 'flock is required (Debian util-linux).'
	exec 9>/run/lock/zram-manager.lock
	flock -n 9 || fatal 'Another zram manager instance is running.'
	if { exec 8<>/dev/tty; } 2>/dev/null; then TTY_FD=8; fi
	init_state
	if ! installed; then first_install; fi
	show_status

	if [[ $ZRAM_NO_MENU == 1 ]]; then
		say 'Status/installation complete; menu skipped.'
	elif [[ -n $TTY_FD ]]; then
		main_menu
	else
		say 'No interactive terminal: status/installation complete; exiting without menu actions.'
	fi

}

# Sourcing defines functions only, allowing isolated tests without host mutations.
if [[ ${BASH_SOURCE[0]:-} == "$0" || -z ${BASH_SOURCE[0]:-} ]]; then
	main "$@"
fi
