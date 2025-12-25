#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'
CONFIG_DIR="/etc/xray_reality"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray_reality.service"
BINARY_PATH="/usr/bin/xray"
DATA_DIR="/data/xray_config_d"

FIRST_RUN=true

function echoColor() {
	case $1 in
	"red") echo -e "\033[31m$2\033[0m" ;;
	"green") echo -e "\033[32m$2\033[0m" ;;
	"yellow") echo -e "\033[33m$2\033[0m" ;;
	"blue") echo -e "\033[36m$2\033[0m" ;;
	"purple") echo -e "\033[1;35m$2\033[0m" ;;
	*) echo -e "$2" ;;
	esac
}

function checkInstallation() {
	if [[ -f "$BINARY_PATH" ]] && [[ -f "$SERVICE_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
		return 0
	else
		return 1
	fi
}

function getPublicIP() {
	PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
	IPV4=$(dig @1.1.1.1 whoami.cloudflare ch txt +short -b $(ip -4 addr show $PRIMARY_INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1) 2>/dev/null | tr -d '"')

	if [[ -z "$IPV4" ]]; then
		IPV4=$(curl -s -4 ifconfig.me 2>/dev/null)
	fi

	if [[ -z "$IPV4" ]]; then
		IPV4=$(curl -s -4 icanhazip.com 2>/dev/null)
	fi

	echo "$IPV4"
}

# Extract public key from private key using xray x25519 -i
# Output format: "Password: <public_key>"
function getPublicKeyFromPrivate() {
	local private_key=$1

	if [[ ! -f "$BINARY_PATH" ]]; then
		return 1
	fi

	if [[ -z "$private_key" ]]; then
		return 1
	fi

	local result=$($BINARY_PATH x25519 -i "$private_key" 2>&1)

	# Parse "Password:" line - this contains the public key
	local pub_key=$(echo "$result" | grep -iE "^Password:" | sed 's/^[^:]*:\s*//' | tr -d ' ')

	# Fallback: get last field of second line
	if [[ -z "$pub_key" ]]; then
		pub_key=$(echo "$result" | sed -n '2p' | awk '{print $NF}')
	fi

	echo "$pub_key"
}

function DownloadxrayRealityCore() {
	echoColor blue "Fetching latest Xray version..."
	version=$(wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')

	if [[ -z "$version" ]]; then
		echoColor red "Failed to fetch version information"
		return 1
	fi

	echoColor green "Latest version: $version"

	get_arch=$(arch)
	temp_f=$(mktemp)
	temp_d=$(mktemp -d)

	echoColor blue "Downloading Xray core..."

	if [ "$get_arch" = "x86_64" ]; then
		wget -q -O $temp_f --no-check-certificate "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-64.zip"
	elif [ "$get_arch" = "aarch64" ]; then
		wget -q -O $temp_f --no-check-certificate "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-arm64-v8a.zip"
	else
		echoColor red "Unsupported architecture: $get_arch"
		return 1
	fi

	unzip -q $temp_f -d $temp_d/
	mv -f $temp_d/xray $BINARY_PATH
	mv -f $temp_d/* /usr/bin/

	chmod 755 $BINARY_PATH

	rm -rf $temp_f $temp_d

	echoColor green "Xray core downloaded successfully!"
	$BINARY_PATH version
}

function createSystemdService() {
	cat <<EOF >$SERVICE_FILE
[Unit]
Description=Xray Reality Service
Documentation=https://github.com/XTLS/xray-core/
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=$BINARY_PATH run -c $CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	echoColor green "Systemd service created!"
}

function installXrayReality() {
	echoColor yellow "===== Installing Xray Reality ====="

	apt update -y
	apt install -y wget curl unzip dnsutils net-tools

	read -p "$(echoColor yellow 'Enter port (default 443, will auto-select in 8s): ')" -t 8 Port
	if [[ -z "$Port" ]]; then
		Port=443
		echoColor blue "Using default port: 443"
	fi

	# Ask for key generation method
	echo ""
	echoColor yellow "Key Generation Options:"
	echoColor blue "  1. Use STATIC keys (default)"
	echoColor blue "  2. Generate NEW random keys"
	read -p "$(echoColor yellow 'Select option (default=1 in 6s): ')" -t 6 key_option

	if [[ -z "$key_option" ]] || [[ "$key_option" == "1" ]]; then
		# Use STATIC keys
		echoColor green "Using STATIC keys..."
		UUID="12345678-1234-1234-1234-123456789012"
		PRIVATE_KEY="YAjoKYIZ601zDTrYJKGoibA0bNTKCboCJNGUH7wgdn4"
		PUBLIC_KEY="N9IY9bJiPgpe_1exP9LGkNHhqmbBL4tDbXc0lQEr9z8"

		echoColor green "✓ Using STATIC credentials"
	else
		# Generate NEW keys
		echoColor green "Generating NEW random keys..."

		# Generate UUID
		UUID=$($BINARY_PATH uuid 2>/dev/null)
		if [[ -z "$UUID" ]]; then
			UUID=$(cat /proc/sys/kernel/random/uuid)
		fi
		echoColor blue "Generated UUID: $UUID"

		# Generate X25519 key pair
		echoColor blue "Generating X25519 key pair..."
		local KEY_OUTPUT=$($BINARY_PATH x25519 2>&1)

		echoColor blue "Raw xray x25519 output:"
		echo "$KEY_OUTPUT"
		echo "---"

		# xray x25519 output format:
		# Private key: <base64_private_key>
		# Public key: <base64_public_key>

		# Parse using multiple methods
		# Method 1: grep for specific patterns
		PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE "^Private" | sed 's/^[^:]*:\s*//' | tr -d ' ')
		PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -iE "^Public" | sed 's/^[^:]*:\s*//' | tr -d ' ')

		echoColor blue "Method 1 - Private: '$PRIVATE_KEY'"
		echoColor blue "Method 1 - Public: '$PUBLIC_KEY'"

		# Method 2: awk extraction (if method 1 fails)
		if [[ -z "$PRIVATE_KEY" ]]; then
			PRIVATE_KEY=$(echo "$KEY_OUTPUT" | head -1 | awk '{print $NF}')
			echoColor blue "Method 2 - Private: '$PRIVATE_KEY'"
		fi
		if [[ -z "$PUBLIC_KEY" ]]; then
			PUBLIC_KEY=$(echo "$KEY_OUTPUT" | sed -n '2p' | awk '{print $NF}')
			echoColor blue "Method 2 - Public: '$PUBLIC_KEY'"
		fi

		# Validate keys
		if [[ -z "$PRIVATE_KEY" ]] || [[ ${#PRIVATE_KEY} -lt 40 ]]; then
			echoColor red "ERROR: Invalid private key generated!"
			echoColor yellow "Falling back to static keys..."
			PRIVATE_KEY="YAjoKYIZ601zDTrYJKGoibA0bNTKCboCJNGUH7wgdn4"
			PUBLIC_KEY="N9IY9bJiPgpe_1exP9LGkNHhqmbBL4tDbXc0lQEr9z8"
		else
			# Derive public key from private key to ensure correctness
			echoColor blue "Verifying by deriving public key from private key..."
			local DERIVED_PUB=$(getPublicKeyFromPrivate "$PRIVATE_KEY")

			if [[ -n "$DERIVED_PUB" ]] && [[ ${#DERIVED_PUB} -ge 40 ]]; then
				echoColor blue "Derived public key: $DERIVED_PUB"
				PUBLIC_KEY="$DERIVED_PUB"
				echoColor green "✓ Using derived public key for accuracy"
			fi
		fi

		echoColor green "✓ Generated NEW credentials"
	fi

	echoColor blue "Getting public IP..."
	PUBLIC_IP=$(getPublicIP)

	if [[ -z "$PUBLIC_IP" ]]; then
		echoColor red "Failed to get public IP!"
		read -p "Please enter your server IP manually: " PUBLIC_IP
	fi

	echo ""
	echoColor yellow "===== Final Configuration ====="
	echoColor green "Server IP: $PUBLIC_IP"
	echoColor green "Port: $Port"
	echoColor green "UUID: $UUID"
	echoColor green "Private Key: $PRIVATE_KEY"
	echoColor green "Public Key: $PUBLIC_KEY"

	mkdir -p $CONFIG_DIR
	mkdir -p $DATA_DIR

	cat <<EOF >$CONFIG_FILE
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $Port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.oracle.com:443",
          "serverNames": [
            "www.oracle.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            ""
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

	createSystemdService

	systemctl enable xray_reality
	systemctl start xray_reality

	sleep 2

	if systemctl is-active --quiet xray_reality; then
		echoColor green "✓ Xray Reality installed and started successfully!"
		generateClientConfig "$PUBLIC_IP" "$Port" "$UUID" "$PUBLIC_KEY"
	else
		echoColor red "✗ Failed to start Xray Reality service"
		systemctl status xray_reality
	fi
}

function generateClientConfig() {
	local ip=$1
	local port=$2
	local uuid=$3
	local pubkey=$4

	# Generate VLESS link
	VLESS_LINK="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.oracle.com&fp=chrome&pbk=${pubkey}&type=tcp&headerType=none#XrayReality-${ip}"

	# Generate client JSON config
	CLIENT_JSON="$DATA_DIR/client_config.json"
	cat <<EOF >$CLIENT_JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$ip",
            "port": $port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.oracle.com",
          "publicKey": "$pubkey",
          "shortId": ""
        }
      },
      "tag": "proxy"
    }
  ]
}
EOF

	# Save connection info
	INFO_FILE="$DATA_DIR/connection_info.txt"
	cat <<EOF >$INFO_FILE
===== Xray Reality Connection Information =====
Server IP: $ip
Port: $port
UUID: $uuid
Public Key: $pubkey
Flow: xtls-rprx-vision
Security: reality
SNI: www.oracle.com
Fingerprint: chrome

===== VLESS Link (Copy & Paste) =====
$VLESS_LINK

===== Client Config Files =====
JSON Config: $CLIENT_JSON
Connection Info: $INFO_FILE

===== Quick Copy =====
Server: $ip:$port
UUID: $uuid
Public Key: $pubkey
EOF

	echo ""
	echoColor green "===== Configuration Saved ====="
	echoColor blue "All configs saved to: $DATA_DIR"
	echo ""
	echoColor yellow "===== VLESS Connection Link ====="
	echo "$VLESS_LINK"
	echo ""
	echoColor yellow "===== Connection Information ====="
	cat "$INFO_FILE"
	echo ""
	echoColor green "===== Files Created ====="
	echoColor blue "- Server config: $CONFIG_FILE"
	echoColor blue "- Client JSON: $CLIENT_JSON"
	echoColor blue "- Connection info: $INFO_FILE"
}

function showStatus() {
	echoColor yellow "===== Xray Reality Status ====="

	if checkInstallation; then
		echoColor green "✓ Installation: Complete"
		echoColor blue "Binary: $BINARY_PATH"
		$BINARY_PATH version | head -1

		echo ""
		if systemctl is-active --quiet xray_reality; then
			echoColor green "✓ Service Status: Running"
		else
			echoColor red "✗ Service Status: Stopped"
		fi

		echo ""
		systemctl status xray_reality --no-pager

		echo ""
		echoColor yellow "===== Current Configuration ====="
		if [[ -f "$CONFIG_FILE" ]]; then
			cat "$CONFIG_FILE"
		fi

		echo ""
		if [[ -f "$DATA_DIR/connection_info.txt" ]]; then
			echoColor yellow "===== Connection Information ====="
			cat "$DATA_DIR/connection_info.txt"
		fi
	else
		echoColor red "✗ Xray Reality is not installed"
	fi
}

function updateXray() {
	echoColor yellow "===== Updating Xray Core ====="

	if [[ ! -f "$BINARY_PATH" ]]; then
		echoColor red "Xray is not installed. Please install first."
		return 1
	fi

	echoColor blue "Current version:"
	$BINARY_PATH version | head -1

	systemctl stop xray_reality

	DownloadxrayRealityCore

	systemctl start xray_reality

	if systemctl is-active --quiet xray_reality; then
		echoColor green "✓ Xray updated and restarted successfully!"
		echoColor blue "New version:"
		$BINARY_PATH version | head -1
	else
		echoColor red "✗ Failed to restart after update"
	fi
}

function stopService() {
	systemctl stop xray_reality
	echoColor green "Xray Reality service stopped"
}

function restartService() {
	systemctl restart xray_reality
	sleep 1
	if systemctl is-active --quiet xray_reality; then
		echoColor green "✓ Xray Reality service restarted successfully!"
	else
		echoColor red "✗ Failed to restart service"
		systemctl status xray_reality
	fi
}

function regenerateClientConfig() {
	echoColor yellow "===== Regenerating Client Configuration ====="

	if [[ ! -f "$CONFIG_FILE" ]]; then
		echoColor red "Server config not found. Please install first."
		return 1
	fi

	# Extract values from server config
	local port=$(grep -oP '"port":\s*\K\d+' "$CONFIG_FILE" | head -1)
	local uuid=$(grep -oP '"id":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
	local private_key=$(grep -oP '"privateKey":\s*"\K[^"]+' "$CONFIG_FILE")

	echoColor blue "Extracted from config:"
	echoColor blue "  Port: $port"
	echoColor blue "  UUID: $uuid"
	echoColor blue "  Private Key: $private_key"

	echoColor blue "Deriving public key from private key..."
	local public_key=$(getPublicKeyFromPrivate "$private_key")

	if [[ -z "$public_key" ]]; then
		echoColor red "Failed to derive public key!"
		return 1
	fi

	echoColor green "  Derived Public Key: $public_key"

	local public_ip=$(getPublicIP)
	if [[ -z "$public_ip" ]]; then
		read -p "Enter server IP: " public_ip
	fi

	generateClientConfig "$public_ip" "$port" "$uuid" "$public_key"
}

function verifyKeys() {
	echoColor yellow "===== Key Verification Tool ====="

	if [[ ! -f "$BINARY_PATH" ]]; then
		echoColor red "Xray binary not found!"
		return 1
	fi

	if [[ ! -f "$CONFIG_FILE" ]]; then
		echoColor red "Config file not found!"
		return 1
	fi

	local private_key=$(grep -oP '"privateKey":\s*"\K[^"]+' "$CONFIG_FILE")
	echoColor blue "Private Key from config: $private_key"

	echoColor blue "Running xray x25519 -i to derive public key..."
	local result=$($BINARY_PATH x25519 -i "$private_key" 2>&1)
	echo "$result"

	local derived_pubkey=$(echo "$result" | grep -iE "^Password:" | sed 's/^[^:]*:\s*//' | tr -d ' ')
	if [[ -z "$derived_pubkey" ]]; then
		derived_pubkey=$(echo "$result" | sed -n '2p' | awk '{print $NF}')
	fi

	echoColor green "Derived Public Key: $derived_pubkey"

	if [[ -f "$DATA_DIR/connection_info.txt" ]]; then
		local saved_pubkey=$(grep "Public Key:" "$DATA_DIR/connection_info.txt" | head -1 | awk '{print $3}')
		echoColor blue "Saved Public Key: $saved_pubkey"

		if [[ "$derived_pubkey" == "$saved_pubkey" ]]; then
			echoColor green "✓ Keys match! Configuration is correct."
		else
			echoColor red "✗ Keys DO NOT match!"
			echoColor yellow "Run option 9 to regenerate client config with correct key"
		fi
	fi
}

function testKeyGeneration() {
	echoColor yellow "===== Testing Key Generation ====="

	if [[ ! -f "$BINARY_PATH" ]]; then
		echoColor red "Xray binary not found!"
		return 1
	fi

	echoColor blue "Testing xray x25519 (generate new key pair)..."
	local output=$($BINARY_PATH x25519 2>&1)
	echo "Raw output:"
	echo "---"
	echo "$output"
	echo "---"

	# Parse keys
	local priv=$(echo "$output" | grep -iE "^Private" | sed 's/^[^:]*:\s*//' | tr -d ' ')
	local pub=$(echo "$output" | grep -iE "^Public" | sed 's/^[^:]*:\s*//' | tr -d ' ')

	# Fallback parsing
	if [[ -z "$priv" ]]; then
		priv=$(echo "$output" | head -1 | awk '{print $NF}')
	fi
	if [[ -z "$pub" ]]; then
		pub=$(echo "$output" | sed -n '2p' | awk '{print $NF}')
	fi

	echoColor green "Parsed Private Key: $priv"
	echoColor green "Parsed Public Key: $pub"

	if [[ -n "$priv" ]] && [[ ${#priv} -ge 40 ]]; then
		echoColor green "✓ Private key looks valid (length: ${#priv})"

		echoColor blue "Verifying by deriving public key from private key..."
		local verify=$($BINARY_PATH x25519 -i "$priv" 2>&1)
		echo "Verification output:"
		echo "$verify"

		local derived=$(echo "$verify" | grep -iE "^Password:" | sed 's/^[^:]*:\s*//' | tr -d ' ')
		if [[ -z "$derived" ]]; then
			derived=$(echo "$verify" | sed -n '2p' | awk '{print $NF}')
		fi

		echoColor green "Derived public key: $derived"

		if [[ "$pub" == "$derived" ]]; then
			echoColor green "✓ Public keys match!"
		else
			echoColor yellow "⚠ Public keys differ - derived key is authoritative"
			echoColor blue "  Parsed: $pub"
			echoColor blue "  Derived: $derived"
		fi
	else
		echoColor red "✗ Failed to parse valid private key!"
	fi
}

function uninstallXray() {
	echoColor red "===== Uninstalling Xray Reality ====="
	read -p "Are you sure you want to uninstall? (yes/no): " confirm

	if [[ "$confirm" != "yes" ]]; then
		echoColor blue "Uninstall cancelled"
		return
	fi

	systemctl stop xray_reality
	systemctl disable xray_reality
	rm -f $SERVICE_FILE
	rm -f $BINARY_PATH
	rm -rf $CONFIG_DIR
	systemctl daemon-reload

	echoColor green "Xray Reality uninstalled (config backup kept in $DATA_DIR)"
}

function showMenu() {
	clear
	echoColor green "======================================="
	echoColor green "   Xray Reality Manager v1.2"
	echoColor green "======================================="
	echo ""

	if checkInstallation; then
		if systemctl is-active --quiet xray_reality; then
			echoColor green "Status: ✓ Installed & Running"
		else
			echoColor yellow "Status: Installed but Stopped"
		fi
	else
		echoColor red "Status: Not Installed"
	fi

	echo ""
	echoColor blue "  1. Install Xray Reality"
	echoColor blue "  2. Show Status & Config"
	echoColor blue "  3. Start Service"
	echoColor blue "  4. Stop Service"
	echoColor blue "  5. Restart Service"
	echoColor blue "  6. Update Xray Core"
	echoColor blue "  7. Show Connection Info"
	echoColor blue "  8. Uninstall"
	echoColor blue "  9. Regenerate Client Config (Fix Keys)"
	echoColor blue " 10. Verify Keys"
	echoColor blue " 11. Test Key Generation"
	echoColor blue "  0. Exit"
	echo ""
}

# Main loop
while true; do
	showMenu
	#read -p "$(echoColor yellow 'Select option: ')" choice
	#read -t 6 -p "$(echoColor yellow 'Select option (default 1 in 6s): ')" choice
	#choice=${choice:-1}

	if [[ "$FIRST_RUN" == "true" ]]; then
		read -t 6 -p "$(echoColor yellow 'Select option (default 1 in 6s): ')" choice
		choice=${choice:-1}
		FIRST_RUN=false
	else
		read -p "$(echoColor yellow 'Select option: ')" choice
	fi

	case $choice in
	1)
		if checkInstallation; then
			echoColor yellow "Xray Reality is already installed!"

			read -t 6 -p "Reinstall? (yes/no, default yes in 6s): " confirm
			confirm=${confirm:-yes}
			if [[ "$confirm" == "yes" ]]; then
				DownloadxrayRealityCore
				installXrayReality
			fi
		########read -p "Reinstall? (yes/no): " confirm
		########if [[ "$confirm" == "yes" ]]; then
		########	DownloadxrayRealityCore
		########	installXrayReality
		########fi
		else
			DownloadxrayRealityCore
			installXrayReality
		fi
		#	read -p "Press Enter to continue..."
		;;
	2)
		showStatus
		read -p "Press Enter to continue..."
		;;
	3)
		systemctl start xray_reality
		echoColor green "Service started"
		read -p "Press Enter to continue..."
		;;
	4)
		stopService
		read -p "Press Enter to continue..."
		;;
	5)
		restartService
		read -p "Press Enter to continue..."
		;;
	6)
		updateXray
		read -p "Press Enter to continue..."
		;;
	7)
		if [[ -f "$DATA_DIR/connection_info.txt" ]]; then
			cat "$DATA_DIR/connection_info.txt"
		else
			echoColor red "No connection info found. Please install first."
		fi
		read -p "Press Enter to continue..."
		;;
	8)
		uninstallXray
		read -p "Press Enter to continue..."
		;;
	9)
		regenerateClientConfig
		read -p "Press Enter to continue..."
		;;
	10)
		verifyKeys
		read -p "Press Enter to continue..."
		;;
	11)
		testKeyGeneration
		read -p "Press Enter to continue..."
		;;
	0)
		echoColor green "Goodbye!"
		exit 0
		;;
	*)
		echoColor red "Invalid option!"
		sleep 1
		;;
	esac
done
