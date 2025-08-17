#!/bin/bash

# BBRv3 Installation Script Selector
# This script allows you to choose between different BBRv3 installation options

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display header
show_header() {
	clear
	echo -e "${CYAN}========================================${NC}"
	echo -e "${CYAN}       BBRv3 Installation Selector     ${NC}"
	echo -e "${CYAN}========================================${NC}"
	echo ""
}

# Function to display menu
show_menu() {
	echo -e "${YELLOW}Please select a BBRv3 installation script:${NC}"
	echo ""
	echo -e "${GREEN}1)${NC} ${BLUE}byJoey's BBRv3 Script${NC}"
	echo -e "   ${PURPLE}Source:${NC} https://github.com/byJoey/Actions-bbr-v3"
	echo -e "   ${PURPLE}Description:${NC} BBRv3 installation script by byJoey"
	echo ""
	echo -e "${GREEN}2)${NC} ${BLUE}Opiran Club VPS Optimizer${NC}"
	echo -e "   ${PURPLE}Source:${NC} https://github.com/opiran-club/VPS-Optimizer"
	echo -e "   ${PURPLE}Description:${NC} VPS optimization script with BBRv3 support"
	echo ""
	echo -e "${GREEN}3)${NC} ${BLUE}Show System Information${NC}"
	echo -e "   ${PURPLE}Description:${NC} Display current kernel and TCP congestion info"
	echo ""
	echo -e "${RED}0)${NC} ${BLUE}Exit${NC}"
	echo ""
}

# Function to show system info
show_system_info() {
	echo -e "${CYAN}Current System Information:${NC}"
	echo -e "${YELLOW}Kernel Version:${NC} $(uname -r)"
	echo -e "${YELLOW}OS:${NC} $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
	echo -e "${YELLOW}Architecture:${NC} $(uname -m)"

	if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
		echo -e "${YELLOW}Current TCP Congestion Control:${NC} $(cat /proc/sys/net/ipv4/tcp_congestion_control)"
	fi

	if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
		echo -e "${YELLOW}Available TCP Congestion Controls:${NC} $(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
	fi
	echo ""
}

# Function to confirm installation
confirm_installation() {
	local script_name="$1"
	echo -e "${YELLOW}You selected: ${GREEN}$script_name${NC}"
	echo -e "${RED}Warning: This will modify your system's kernel parameters and TCP congestion control.${NC}"
	echo -e "${RED}Make sure you have a backup or snapshot of your system before proceeding.${NC}"
	echo ""
	read -p "Do you want to continue? (y/N): " confirm

	case $confirm in
	[yY] | [yY][eE][sS])
		return 0
		;;
	*)
		echo -e "${YELLOW}Installation cancelled.${NC}"
		return 1
		;;
	esac
}

# Function to run byJoey's script
install_byjoey() {
	if confirm_installation "byJoey's BBRv3 Script"; then
		echo -e "${GREEN}Running byJoey's BBRv3 installation script...${NC}"
		echo -e "${CYAN}Command: bash <(curl -l -s https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)${NC}"
		echo ""
		bash <(curl -l -s https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)
	fi
}

# Function to run Opiran Club script
install_opiran() {
	if confirm_installation "Opiran Club VPS Optimizer"; then
		echo -e "${GREEN}Running Opiran Club VPS Optimizer script...${NC}"
		echo -e "${CYAN}Command: bash <(curl -s https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/optimizer.sh --ipv4)${NC}"
		echo ""
		bash <(curl -s https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/optimizer.sh --ipv4)
	fi
}

# Main function
main() {
	while true; do
		show_header
		show_menu

		read -p "Enter your choice [0-3]: " choice
		echo ""

		case $choice in
		1)
			install_byjoey
			read -p "Press Enter to continue..."
			;;
		2)
			install_opiran
			read -p "Press Enter to continue..."
			;;
		3)
			show_system_info
			read -p "Press Enter to continue..."
			;;
		0)
			echo -e "${GREEN}Goodbye!${NC}"
			exit 0
			;;
		*)
			echo -e "${RED}Invalid option. Please choose 0-3.${NC}"
			read -p "Press Enter to continue..."
			;;
		esac
	done
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
	echo -e "${RED}Warning: Running as root user.${NC}"
else
	echo -e "${YELLOW}Note: You may need to run this script with sudo for system modifications.${NC}"
fi

# Start the script
main
