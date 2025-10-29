#!/bin/bash

# Script to configure /run mount with custom inode settings
# Must be run as root

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
	echo -e "${RED}Error: This script must be run as root${NC}"
	exit 1
fi

echo "=================================================="
echo "  /run Mount Inode Configuration Manager"
echo "=================================================="
echo

# Get current inode statistics
get_inode_info() {
	local mount_point=$1
	df -i "$mount_point" | awk 'NR==2 {print $2, $3, $4, $5}'
}

# Display current inode usage
echo -e "${GREEN}Current Inode Usage:${NC}"
echo "-------------------"

# Get / inode info
root_info=($(get_inode_info /))
root_total=${root_info[0]}
root_used=${root_info[1]}
root_available=${root_info[2]}
root_percent=${root_info[3]}

echo "/ (root filesystem):"
echo "  Total inodes: $root_total"
echo "  Used inodes: $root_used"
echo "  Available inodes: $root_available"
echo "  Usage: $root_percent"
echo

# Get /run inode info
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

# Ask user if they want to increase inodes
echo -e "${YELLOW}Do you want to increase inodes for /run? (yes/no) [default: no]${NC}"
read -r increase_inodes
increase_inodes=${increase_inodes:-no}

if [[ ! "$increase_inodes" =~ ^[Yy][Ee][Ss]$ ]]; then
	echo -e "${GREEN}No changes made. Exiting.${NC}"
	exit 0
fi

# Ask for multiplier
echo
echo -e "${YELLOW}Enter the multiplier for current inode count (e.g., 5 for 5x) [default: 5]${NC}"
read -r multiplier
multiplier=${multiplier:-5}

# Validate multiplier is a positive number
if ! [[ "$multiplier" =~ ^[0-9]+$ ]] || [ "$multiplier" -lt 1 ]; then
	echo -e "${RED}Error: Multiplier must be a positive integer${NC}"
	exit 1
fi

# Calculate new inode count
new_inode_count=$((run_total * multiplier))
echo
echo -e "${GREEN}New inode count will be: $new_inode_count (${multiplier}x current: $run_total)${NC}"
echo

# Create systemd mount unit
MOUNT_UNIT="/etc/systemd/system/run.mount"

echo "Creating systemd mount unit at $MOUNT_UNIT..."

cat >"$MOUNT_UNIT" <<EOF
[Unit]
Description=Temporary File System for /run
DefaultDependencies=no
Before=local-fs.target
After=swap.target
Conflicts=umount.target

[Mount]
What=tmpfs
Where=/run
Type=tmpfs
Options=mode=0755,nosuid,nodev,nr_inodes=${new_inode_count}

[Install]
WantedBy=local-fs.target
EOF

echo -e "${GREEN}Mount unit created successfully.${NC}"
echo

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo -e "${YELLOW}Note: The changes will take effect after the next reboot.${NC}"
echo -e "${YELLOW}To apply immediately, you would need to:${NC}"
echo -e "${YELLOW}  1. Stop all services using /run${NC}"
echo -e "${YELLOW}  2. Remount /run with new options${NC}"
echo -e "${YELLOW}  This is risky and may require a reboot anyway.${NC}"
echo

# Enable the mount unit
echo "Enabling run.mount unit..."
systemctl enable run.mount

echo
echo "=================================================="
echo -e "${GREEN}Configuration Complete!${NC}"
echo "=================================================="
echo
echo "Summary:"
echo "  - Old inode count: $run_total"
echo "  - New inode count: $new_inode_count (${multiplier}x)"
echo "  - Mount unit: $MOUNT_UNIT"
echo "  - Status: Enabled (will activate on next boot)"
echo
echo -e "${YELLOW}Reboot your system for changes to take effect.${NC}"
echo

# Show final inode info (current state)
echo "Current Inode Usage (before immediate remount):"
echo "------------------------------------------------"
echo "/ usage: $root_percent"
echo "/run usage: $run_percent"
echo

# Ask if user wants to apply changes immediately
echo -e "${YELLOW}Do you want to apply the inode changes immediately (requires remounting /run)? (yes/no) [default: yes]${NC}"
echo -e "${RED}WARNING: This will temporarily unmount /run - some services may be affected!${NC}"
read -r apply_now
apply_now=${apply_now:-yes}

if [[ "$apply_now" =~ ^[Yy][Ee][Ss]$ ]]; then
	echo
	echo "Applying changes immediately..."
	echo "Step 1: Remounting /run with new inode count..."

	# Remount /run with new options (temporary until reboot)
	if mount -o remount,mode=0755,nosuid,nodev,nr_inodes=${new_inode_count} /run; then
		echo -e "${GREEN}Successfully remounted /run with new inode count!${NC}"
		echo

		# Get updated inode info
		echo "Updated Inode Usage (immediately effective):"
		echo "--------------------------------------------"

		# Get new / inode info
		root_info_new=($(get_inode_info /))
		root_percent_new=${root_info_new[3]}

		# Get new /run inode info
		run_info_new=($(get_inode_info /run))
		run_total_new=${run_info_new[0]}
		run_used_new=${run_info_new[1]}
		run_available_new=${run_info_new[2]}
		run_percent_new=${run_info_new[3]}

		echo "/ usage: $root_percent_new"
		echo "/run filesystem:"
		echo "  Total inodes: $run_total_new"
		echo "  Used inodes: $run_used_new"
		echo "  Available inodes: $run_available_new"
		echo "  Usage: $run_percent_new"
		echo

		echo -e "${GREEN}Changes are now in effect!${NC}"
		echo "  - Current (immediate): $run_total_new inodes"
		echo "  - After reboot (permanent): $new_inode_count inodes"
		echo

		if [ "$run_total_new" -eq "$new_inode_count" ]; then
			echo -e "${GREEN}✓ Current and post-reboot inode counts are aligned!${NC}"
		else
			echo -e "${YELLOW}Note: Values may differ slightly due to system overhead.${NC}"
		fi
	else
		echo -e "${RED}Failed to remount /run. Changes will still apply after reboot.${NC}"
	fi
else
	echo
	echo -e "${YELLOW}Immediate changes skipped. Changes will apply after reboot.${NC}"
	echo "Current /run usage: $run_percent"
fi
echo
