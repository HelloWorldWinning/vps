#!/bin/bash

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_msg() {
	echo -e "${2}${1}${NC}"
}

# Function to safely disable swap
safe_swapoff() {
	local swap_location=$1
	local max_retries=5
	local retry_count=0

	while [ $retry_count -lt $max_retries ]; do
		if swapoff "$swap_location" 2>/dev/null; then
			print_msg "Successfully disabled swap: $swap_location" "$GREEN"
			return 0
		fi

		retry_count=$((retry_count + 1))

		if [ $retry_count -lt $max_retries ]; then
			print_msg "Failed to disable swap (attempt $retry_count/$max_retries). Waiting 5 seconds..." "$YELLOW"
			sleep 5

			# Try to free up some memory
			sync
			echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || true
		fi
	done

	print_msg "Warning: Could not disable swap at $swap_location after $max_retries attempts" "$YELLOW"
	return 1
}

# Function to check if swap file is in use
is_swap_active() {
	swapon --show=NAME --noheadings | grep -q "$1"
}

# 1. Get Human Readable values (for display)
read sw_total_h sw_used_h sw_free_h <<<$(free -h | awk '/^Swap:/ {print $2, $3, $4}')

# 2. Calculate Percentages
# We run 'free' (raw numbers) to do the math, as 'free -h' (2.0Gi) is hard to calculate with.
read pct_used pct_free <<<$(free | awk '/^Swap:/ { 
    if ($2 > 0) {
        print ($3/$2)*100, ($4/$2)*100 
    } else {
        print 0, 0 
    }
}')

# 3. Get Active Swap Files
current_swap_files=$(swapon --show=NAME --noheadings | tr '\n' ', ' | sed 's/, $//')

# 4. Display the Dashboard
echo "=========================================="
echo "         CURRENT SWAP OVERVIEW            "
echo "=========================================="
printf "  %-15s : %s\n" "Total Size" "$sw_total_h"
printf "  %-15s : %s (%.1f%%)\n" "Taken Up" "$sw_used_h" "$pct_used"
printf "  %-15s : %s (%.1f%%)\n" "Free Space" "$sw_free_h" "$pct_free"
echo "------------------------------------------"
if [ -z "$current_swap_files" ]; then
	printf "  %-15s : %s\n" "Active File(s)" "None"
else
	printf "  %-15s : %s\n" "Active File(s)" "$current_swap_files"
fi
echo "=========================================="
echo ""

# Prompt user for the size of the new swap file
read -p "Enter the size of the swap file in GB (e.g., '1' for 1GB, '1.5' for 1.5GB, default is 5): " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-5}

# Validate input
if ! [[ "$SWAP_SIZE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
	print_msg "Invalid input. Please enter a numeric value." "$RED"
	exit 1
fi

SWAP_SIZE="${SWAP_SIZE}G"

print_msg "\nStarting swap configuration for size: $SWAP_SIZE" "$GREEN"

## Check available disk space
#AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1048576)}') # Available space in GB
#REQUIRED_SPACE=$(echo "$SWAP_SIZE" | sed 's/G//')
#REQUIRED_SPACE_MB=$(echo "$REQUIRED_SPACE * 1024" | bc | cut -d. -f1)
#
##if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE_MB" ]; then
##	print_msg "Error: Not enough disk space. Available: ${AVAILABLE_SPACE}GB, Required: ${REQUIRED_SPACE}GB" "$RED"
##	exit 1
##fi
#
#if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
#	print_msg "Error: Not enough disk space. Available: ${AVAILABLE_SPACE}GB, Required: ${REQUIRED_SPACE}GB" "$RED"
#	exit 1
#fi

# Check available disk space
# Calculate Available space in MB (df output is usually 1K blocks, so divide by 1024)
AVAILABLE_SPACE_MB=$(df / | awk 'NR==2 {print int($4/1024)}')
AVAILABLE_SPACE_GB=$(echo "$AVAILABLE_SPACE_MB / 1024" | bc)

REQUIRED_SPACE=$(echo "$SWAP_SIZE" | sed 's/G//')
REQUIRED_SPACE_MB=$(echo "$REQUIRED_SPACE * 1024" | bc | cut -d. -f1)

# Compare MB against MB
if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
	print_msg "Error: Not enough disk space. Available: ${AVAILABLE_SPACE_GB}GB (${AVAILABLE_SPACE_MB}MB), Required: ${REQUIRED_SPACE}GB" "$RED"
	exit 1
fi

# Get current memory usage to determine if we can safely disable swap
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_AVAILABLE=$(free -m | awk 'NR==2{print $7}')
SWAP_USED=$(free -m | awk 'NR==3{print $3}')

print_msg "\nMemory Status:" "$YELLOW"
print_msg "Total RAM: ${MEM_TOTAL}MB" "$NC"
print_msg "Used RAM: ${MEM_USED}MB" "$NC"
print_msg "Available RAM: ${MEM_AVAILABLE}MB" "$NC"
print_msg "Swap Used: ${SWAP_USED}MB" "$NC"

# Check if we have enough RAM to safely disable swap
if [ "$SWAP_USED" -gt 0 ] && [ "$MEM_AVAILABLE" -lt "$SWAP_USED" ]; then
	print_msg "\nWarning: Not enough available RAM to safely disable swap!" "$RED"
	print_msg "Swap used: ${SWAP_USED}MB, Available RAM: ${MEM_AVAILABLE}MB" "$RED"
	read -p "Do you want to continue anyway? This might cause system instability (y/N): " CONTINUE
	if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
		print_msg "Operation cancelled." "$YELLOW"
		exit 0
	fi
fi

# Backup fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
print_msg "\nBacked up /etc/fstab" "$GREEN"

# Identify all swap locations
SWAP_LOCATIONS=$(swapon --show=NAME --noheadings 2>/dev/null || true)

# Disable all existing swap
if [ -n "$SWAP_LOCATIONS" ]; then
	print_msg "\nDisabling existing swap..." "$YELLOW"
	for LOCATION in $SWAP_LOCATIONS; do
		safe_swapoff "$LOCATION"

		# Comment out in fstab
		if grep -q "^[^#].*$LOCATION" /etc/fstab; then
			sed -i "\|$LOCATION| s/^/#/" /etc/fstab
			print_msg "Commented out $LOCATION in /etc/fstab" "$GREEN"
		fi
	done
else
	print_msg "\nNo active swap found." "$YELLOW"
fi

# Remove old swap file if it exists
if [ -f /swapfile ]; then
	print_msg "\nRemoving old swap file..." "$YELLOW"

	# Make sure it's not being used
	if is_swap_active "/swapfile"; then
		safe_swapoff "/swapfile"
	fi

	# Try to remove the file with retries
	max_retries=5
	retry_count=0

	while [ $retry_count -lt $max_retries ]; do
		if rm -f /swapfile 2>/dev/null; then
			print_msg "Successfully removed old swap file" "$GREEN"
			break
		fi

		retry_count=$((retry_count + 1))

		if [ $retry_count -lt $max_retries ]; then
			print_msg "Failed to remove swap file (attempt $retry_count/$max_retries). Waiting..." "$YELLOW"
			sleep 2

			# Make sure it's really not mounted
			swapoff /swapfile 2>/dev/null || true

			# Try to release the file
			lsof /swapfile 2>/dev/null || true
		else
			print_msg "Error: Could not remove old swap file after $max_retries attempts" "$RED"
			print_msg "You may need to reboot the system and run this script again." "$RED"
			exit 1
		fi
	done
fi

# Remove any existing /swapfile entries from fstab
sed -i '/\/swapfile/d' /etc/fstab

print_msg "\nCreating new swap file of size $SWAP_SIZE..." "$YELLOW"

# Create new swap file using dd for better compatibility
# fallocate doesn't work on all filesystems (like XFS)
SWAP_SIZE_MB=$(echo "$SWAP_SIZE" | sed 's/G//' | awk '{print int($1 * 1024)}')

if command -v fallocate >/dev/null 2>&1; then
	# Try fallocate first (faster)
	if fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null; then
		print_msg "Swap file created using fallocate" "$GREEN"
	else
		print_msg "fallocate failed, using dd instead..." "$YELLOW"
		dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB" status=progress
		print_msg "Swap file created using dd" "$GREEN"
	fi
else
	# Use dd if fallocate is not available
	dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB" status=progress
	print_msg "Swap file created using dd" "$GREEN"
fi

# Secure the swap file
print_msg "Securing swap file permissions..." "$YELLOW"
chmod 600 /swapfile
chown root:root /swapfile

# Make it a swap file
print_msg "Formatting swap file..." "$YELLOW"
mkswap /swapfile

# Activate the swap file
print_msg "Activating swap file..." "$YELLOW"
if swapon /swapfile; then
	print_msg "Swap file activated successfully" "$GREEN"
else
	print_msg "Error: Failed to activate swap file" "$RED"
	exit 1
fi

# Add to fstab for persistence
print_msg "Adding swap file to /etc/fstab..." "$YELLOW"
echo '/swapfile none swap sw 0 0' >>/etc/fstab

# Configure swappiness
print_msg "\nConfiguring swappiness..." "$YELLOW"
sysctl vm.swappiness=10

# Make swappiness permanent
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
	echo 'vm.swappiness=10' >>/etc/sysctl.conf
else
	sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
fi

# Show final swap status
print_msg "\n========================================" "$GREEN"
print_msg "Swap configuration completed successfully!" "$GREEN"
print_msg "========================================" "$NC"
print_msg "\nFinal swap status:" "$YELLOW"
free -h
echo
swapon --show

print_msg "\nSwap file of size $SWAP_SIZE created and activated." "$GREEN"
