#!/bin/bash

# Script to configure /run mount with custom inode settings via /etc/fstab
# Must be run as root

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
	echo -e "${RED}Error: This script must be run as root${NC}"
	exit 1
fi

echo "=================================================="
echo "  /run Mount Inode Configuration Manager (fstab)"
echo "=================================================="
echo

get_inode_info() {
	local mount_point=$1
	df -i "$mount_point" | awk 'NR==2 {print $2, $3, $4, $5}'
}

echo -e "${GREEN}Current Inode Usage:${NC}"
echo "-------------------"

root_info=($(get_inode_info /))
echo "/ (root filesystem):"
echo "  Total inodes: ${root_info[0]}"
echo "  Used inodes: ${root_info[1]}"
echo "  Available inodes: ${root_info[2]}"
echo "  Usage: ${root_info[3]}"
echo

run_info=($(get_inode_info /run))
run_total=${run_info[0]}
run_used=${run_info[1]}
run_available=${run_info[2]}
run_percent=${run_info[3]}

echo "/run filesystem:"
echo "  Total inodes: $run_total"
echo "  Used inodes: $run_used"
echo "  Available inodes: $run_available"
echo "  Usage: $run_percent"
echo

echo -e "${YELLOW}Do you want to increase inodes for /run? (yes/no) [default: no]${NC}"
read -r increase_inodes
increase_inodes=${increase_inodes:-no}

if [[ ! "$increase_inodes" =~ ^[Yy][Ee][Ss]$ ]]; then
	echo -e "${GREEN}No changes made. Exiting.${NC}"
	exit 0
fi

echo
echo -e "${YELLOW}Enter the multiplier for current inode count (e.g., 5 for 5x) [default: 5]${NC}"
read -r multiplier
multiplier=${multiplier:-5}

if ! [[ "$multiplier" =~ ^[0-9]+$ ]] || [ "$multiplier" -lt 1 ]; then
	echo -e "${RED}Error: Multiplier must be a positive integer${NC}"
	exit 1
fi

new_inode_count=$((run_total * multiplier))
echo
echo -e "${GREEN}New inode count will be: $new_inode_count (${multiplier}x current: $run_total)${NC}"
echo

# Backup fstab
cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d_%H%M%S)
echo -e "${GREEN}Backed up /etc/fstab${NC}"

# Remove any existing /run entry
sed -i.tmp '/^[^#]*[[:space:]]\/run[[:space:]]/d' /etc/fstab

# Add new /run entry
echo "tmpfs   /run   tmpfs   mode=0755,nosuid,nodev,nr_inodes=${new_inode_count}   0 0" >>/etc/fstab

echo -e "${GREEN}Updated /etc/fstab with new /run configuration${NC}"
echo

# Remove systemd mount unit if it exists (cleanup from old script)
if [ -f "/etc/systemd/system/run.mount" ]; then
	echo -e "${YELLOW}Found old run.mount unit, removing it...${NC}"
	systemctl disable run.mount 2>/dev/null || true
	rm -f /etc/systemd/system/run.mount
	systemctl daemon-reload
	echo -e "${GREEN}Cleaned up old systemd mount unit${NC}"
fi

echo "=================================================="
echo -e "${GREEN}Configuration Complete!${NC}"
echo "=================================================="
echo
echo "Summary:"
echo "  - Old inode count: $run_total"
echo "  - New inode count: $new_inode_count (${multiplier}x)"
echo "  - Configuration: /etc/fstab"
echo "  - Backup: /etc/fstab.bak.*"
echo
echo -e "${YELLOW}Changes will take effect after reboot.${NC}"
echo

echo -e "${YELLOW}Do you want to apply changes immediately (remount /run)? (yes/no) [default: no]${NC}"
echo -e "${RED}WARNING: This may briefly interrupt services using /run!${NC}"
read -r apply_now
apply_now=${apply_now:-no}

if [[ "$apply_now" =~ ^[Yy][Ee][Ss]$ ]]; then
	echo
	echo "Applying changes immediately..."

	if mount -o remount,mode=0755,nosuid,nodev,nr_inodes=${new_inode_count} /run; then
		echo -e "${GREEN}Successfully remounted /run!${NC}"
		echo

		run_info_new=($(get_inode_info /run))
		echo "Updated /run filesystem:"
		echo "  Total inodes: ${run_info_new[0]}"
		echo "  Used inodes: ${run_info_new[1]}"
		echo "  Available inodes: ${run_info_new[2]}"
		echo "  Usage: ${run_info_new[3]}"
		echo

		if [ "${run_info_new[0]}" -eq "$new_inode_count" ]; then
			echo -e "${GREEN}✓ Changes applied successfully!${NC}"
		else
			echo -e "${YELLOW}Note: Actual value may differ slightly.${NC}"
		fi
	else
		echo -e "${RED}Failed to remount. Changes will apply after reboot.${NC}"
	fi
else
	echo
	echo -e "${YELLOW}Immediate changes skipped. Reboot to apply.${NC}"
fi

echo
echo "To verify after reboot, run: df -i /run"
echo
