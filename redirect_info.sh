#!/bin/bash

# IPTables NAT Redirect Port Information Viewer
# Usage: ./redirect_info.sh [option]
# Default (no option): Shows PREROUTING chain with line numbers
# Options: 1-5 for different levels of detail

show_help() {
	echo "IPTables NAT Redirect Port Information Viewer"
	echo "============================================="
	echo "Usage: $0 [option]"
	echo ""
	echo "Options:"
	echo "  (default) - PREROUTING chain with line numbers (quick view)"
	echo "  1         - PREROUTING chain with line numbers (same as default)"
	echo "  2         - All NAT table chains"
	echo "  3         - All NAT + REDIRECT/DNAT rules analysis"
	echo "  4         - Complete NAT info + active connections"
	echo "  5         - Full system port redirect analysis"
	echo "  help|-h   - Show this help message"
	echo ""
}

# Function to check if running as root or with sudo
check_permissions() {
	if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
		echo "Warning: This script requires root privileges or sudo access."
		echo "Some information may not be available."
		echo ""
	fi
}

# Function to run iptables command with proper privileges
run_iptables() {
	if [[ $EUID -eq 0 ]]; then
		iptables "$@"
	else
		sudo iptables "$@"
	fi
}

# Function to run other commands with proper privileges
run_privileged() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

# Level 1: PREROUTING chain with line numbers (default)
show_prerouting() {
	echo "=== NAT PREROUTING Chain (Port Redirects) ==="
	echo "Showing rules with line numbers for easy management:"
	echo ""
	run_iptables -t nat -L PREROUTING -v -n --line-numbers
	echo ""
}

# Level 2: All NAT table chains
show_all_nat() {
	echo "=== Complete NAT Table ==="
	echo "All chains in NAT table:"
	echo ""
	run_iptables -t nat -L -v -n
	echo ""
}

# Level 3: NAT + REDIRECT/DNAT analysis
show_redirect_analysis() {
	show_all_nat

	echo "=== PORT REDIRECT ANALYSIS ==="
	echo ""

	# Find REDIRECT rules
	echo "--- REDIRECT Rules ---"
	run_iptables -t nat -S | grep -i redirect || echo "No REDIRECT rules found"
	echo ""

	# Find DNAT rules
	echo "--- DNAT Rules ---"
	run_iptables -t nat -S | grep -i dnat || echo "No DNAT rules found"
	echo ""

	# Find SNAT/MASQUERADE rules
	echo "--- SNAT/MASQUERADE Rules ---"
	run_iptables -t nat -S | grep -E "(SNAT|MASQUERADE)" || echo "No SNAT/MASQUERADE rules found"
	echo ""
}

# Level 4: Complete NAT info + active connections
show_complete_info() {
	show_redirect_analysis

	echo "=== ACTIVE CONNECTION TRACKING ==="
	echo ""

	# Show conntrack info if available
	if command -v conntrack >/dev/null 2>&1; then
		echo "--- Active NAT Connections ---"
		run_privileged conntrack -L -p tcp 2>/dev/null | grep -E "(DNAT|SNAT)" | head -10 || echo "No active NAT connections found"
		echo ""
	else
		echo "conntrack tool not available - install conntrack-tools for connection tracking info"
		echo ""
	fi

	# Show /proc/net/nf_conntrack if available
	if [[ -r /proc/net/nf_conntrack ]]; then
		echo "--- Recent NAT Connections (from /proc/net/nf_conntrack) ---"
		run_privileged head -10 /proc/net/nf_conntrack 2>/dev/null | grep -E "(dnat|snat)" || echo "No recent NAT entries found"
		echo ""
	fi
}

# Level 5: Full system port redirect analysis
show_full_analysis() {
	show_complete_info

	echo "=== SYSTEM PORT ANALYSIS ==="
	echo ""

	# Show listening ports
	echo "--- Currently Listening Ports ---"
	if command -v ss >/dev/null 2>&1; then
		ss -tlnp | head -15
	elif command -v netstat >/dev/null 2>&1; then
		netstat -tlnp | head -15
	else
		echo "Neither ss nor netstat available"
	fi
	echo ""

	# Show iptables rules in all relevant tables
	echo "--- FILTER Table (may affect redirected traffic) ---"
	run_iptables -L -n | grep -E "(ACCEPT|DROP|REJECT|FORWARD)" | head -10
	echo ""

	# Show mangle table if it has rules
	echo "--- MANGLE Table (traffic modification) ---"
	mangle_rules=$(run_iptables -t mangle -L -n | grep -v "^Chain\|^target" | grep -v "^$" | wc -l)
	if [[ $mangle_rules -gt 0 ]]; then
		run_iptables -t mangle -L -n | head -10
	else
		echo "No significant MANGLE rules found"
	fi
	echo ""

	# Show raw table if it has rules
	echo "--- RAW Table (connection tracking bypass) ---"
	raw_rules=$(run_iptables -t raw -L -n | grep -v "^Chain\|^target" | grep -v "^$" | wc -l)
	if [[ $raw_rules -gt 0 ]]; then
		run_iptables -t raw -L -n | head -10
	else
		echo "No significant RAW rules found"
	fi
	echo ""

	# Show kernel modules related to NAT
	echo "--- NAT-related Kernel Modules ---"
	lsmod | grep -E "(nat|conntrack|netfilter)" || echo "No NAT modules visible"
	echo ""
}

# Show interactive menu
show_menu() {
	echo "============================================="
	echo "   IPTables NAT Redirect Info Viewer"
	echo "============================================="
	echo ""
	echo "Select view level:"
	echo ""
	echo "  [1] PREROUTING chain (default - quick view)"
	echo "  [2] All NAT table chains"
	echo "  [3] NAT + REDIRECT/DNAT analysis"
	echo "  [4] Complete NAT + active connections"
	echo "  [5] Full system port redirect analysis"
	echo "  [h] Help - detailed description"
	echo "  [q] Quit"
	echo ""
	echo -n "Enter your choice [1-5, h, q]: "
}

# Main script logic
main() {
	check_permissions

	while true; do
		show_menu
		read -r choice
		echo ""

		case "$choice" in
		"" | "1")
			show_prerouting
			;;
		"2")
			show_all_nat
			;;
		"3")
			show_redirect_analysis
			;;
		"4")
			show_complete_info
			;;
		"5")
			show_full_analysis
			;;
		"h" | "H" | "help")
			show_help
			;;
		"q" | "Q" | "quit" | "exit")
			echo "Goodbye!"
			exit 0
			;;
		*)
			echo "Invalid option: $choice"
			echo "Please enter 1-5, h for help, or q to quit"
			;;
		esac

		echo ""
		echo "Press Enter to continue..."
		read -r
		clear
	done
}

# Run main function
main
