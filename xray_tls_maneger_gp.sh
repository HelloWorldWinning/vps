#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

CONFIG_DIR="/etc/xray_tls"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray_tls.service"
BINARY_PATH="/usr/bin/xray"
DATA_DIR="/data/xray_config_tls_d"
CERT_DIR="/etc/ssl/private"
CERT_FILE="$CERT_DIR/fullchain.cer"
KEY_FILE="$CERT_DIR/private.key"
ACME_SH="/root/.acme.sh/acme.sh"

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

function DownloadxrayTlsCore() {
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
	cat <<EOF2 >$SERVICE_FILE
[Unit]
Description=Xray TLS Service (VLESS-TCP-XTLS-Vision)
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
EOF2

	systemctl daemon-reload
	echoColor green "Systemd service created!"
}

function installAcmeSh() {
	if [[ -f "$ACME_SH" ]]; then
		return 0
	fi

	echoColor yellow "acme.sh not found, installing..."
	curl https://get.acme.sh | sh
	if [[ $? -ne 0 ]]; then
		echoColor red "Failed to install acme.sh"
		return 1
	fi

	if [[ -f "/root/.acme.sh/acme.sh" ]]; then
		ACME_SH="/root/.acme.sh/acme.sh"
	fi

	echoColor green "acme.sh installed successfully!"
}

function issueCertificate() {
	local domain=$1

	if [[ -z "$domain" ]]; then
		echoColor red "Domain is empty, cannot issue certificate."
		return 1
	fi

	installAcmeSh || return 1

	mkdir -p "$CERT_DIR"

	echoColor blue "Issuing certificate for domain: $domain (standalone mode on port 80)..."

	$ACME_SH --set-default-ca --server letsencrypt >/dev/null 2>&1

	$ACME_SH --issue --standalone -d "$domain" --keylength ec-256
	if [[ $? -ne 0 ]]; then
		echoColor red "acme.sh failed to issue certificate!"
		return 1
	fi

	$ACME_SH --install-cert -d "$domain" \
		--key-file "$KEY_FILE" \
		--fullchain-file "$CERT_FILE" >/dev/null 2>&1

	if [[ $? -ne 0 ]]; then
		echoColor red "acme.sh failed to install certificate!"
		return 1
	fi

	echoColor green "Certificate issued and installed successfully!"
	echoColor blue "  Certificate: $CERT_FILE"
	echoColor blue "  Private key: $KEY_FILE"
}

function installXrayTls() {
	echoColor yellow "===== Installing Xray TLS (VLESS-TCP-XTLS-Vision) ====="

	apt update -y
	apt install -y wget curl unzip dnsutils net-tools socat

	local Domain
	echo ""
	read -p "$(echoColor yellow 'Enter your domain (must point to this server): ')" Domain
	if [[ -z "$Domain" ]]; then
		echoColor red "Domain cannot be empty!"
		return 1
	fi

	read -t 8 -p "$(echoColor yellow 'Enter port (default 443, auto-select in 8s): ')" Port
	if [[ -z "$Port" ]]; then
		Port=443
		echoColor blue "Using default port: 443"
	fi

	echoColor blue "Generating UUID..."
	UUID=$($BINARY_PATH uuid 2>/dev/null)
	if [[ -z "$UUID" ]]; then
		UUID=$(cat /proc/sys/kernel/random/uuid)
	fi
	echoColor green "UUID: $UUID"

	echoColor blue "Getting public IP..."
	PUBLIC_IP=$(getPublicIP)
	echoColor green "Public IP: $PUBLIC_IP"

	echo ""
	echoColor yellow "===== Issuing TLS certificate via acme.sh ====="
	issueCertificate "$Domain"
	if [[ $? -ne 0 ]]; then
		echoColor red "Certificate issuance failed. Aborting installation."
		return 1
	fi

	mkdir -p "$CONFIG_DIR"
	mkdir -p "$DATA_DIR"

	cat <<EOF3 >$CONFIG_FILE
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
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
        "security": "tls",
        "tlsSettings": {
          "rejectUnknownSni": true,
          "minVersion": "1.2",
          "certificates": [
            {
              "ocspStapling": 3600,
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
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
EOF3

	createSystemdService

	systemctl enable xray_tls
	systemctl start xray_tls

	sleep 2

	if systemctl is-active --quiet xray_tls; then
		echoColor green "✓ Xray TLS installed and started successfully!"
		generateClientConfig "$Domain" "$Port" "$UUID"
	else
		echoColor red "✗ Failed to start Xray TLS service"
		systemctl status xray_tls
	fi
}

function generateClientConfig() {
	local domain=$1
	local port=$2
	local uuid=$3

	local VLESS_LINK="vless://${uuid}@${domain}:${port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${domain}&fp=chrome&type=tcp&headerType=none#XrayTLS-${domain}"

	local CLIENT_JSON="$DATA_DIR/client_config.json"
	cat <<EOF4 >$CLIENT_JSON
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "geosite:cn",
          "geosite:private"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn",
          "geoip:private"
        ],
        "outboundTag": "direct"
      }
    ]
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
          "tls"
        ]
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$domain",
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
        "security": "tls",
        "tlsSettings": {
          "serverName": "$domain",
          "allowInsecure": false,
          "fingerprint": "chrome"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF4

	local INFO_FILE="$DATA_DIR/connection_info.txt"
	cat <<EOF5 >$INFO_FILE
===== Xray TLS (VLESS-TCP-XTLS-Vision) Connection Information =====
Domain: $domain
Port: $port
UUID: $uuid
Flow: xtls-rprx-vision
Security: tls
SNI: $domain
Fingerprint: chrome

===== VLESS Link (Copy & Paste) =====
$VLESS_LINK

===== Client Config Files =====
JSON Config: $CLIENT_JSON
Connection Info: $INFO_FILE

===== Quick Copy =====
Server: $domain:$port
UUID: $uuid
EOF5

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
	echoColor yellow "===== Xray TLS Status ====="

	if checkInstallation; then
		echoColor green "✓ Installation: Complete"
		echoColor blue "Binary: $BINARY_PATH"
		$BINARY_PATH version | head -1

		echo ""
		if systemctl is-active --quiet xray_tls; then
			echoColor green "✓ Service Status: Running"
		else
			echoColor red "✗ Service Status: Stopped"
		fi

		echo ""
		systemctl status xray_tls --no-pager

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
		echoColor red "✗ Xray TLS is not installed"
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

	systemctl stop xray_tls

	DownloadxrayTlsCore

	systemctl start xray_tls

	if systemctl is-active --quiet xray_tls; then
		echoColor green "✓ Xray updated and restarted successfully!"
		echoColor blue "New version:"
		$BINARY_PATH version | head -1
	else
		echoColor red "✗ Failed to restart after update"
	fi
}

function stopService() {
	systemctl stop xray_tls
	echoColor green "Xray TLS service stopped"
}

function restartService() {
	systemctl restart xray_tls
	sleep 1
	if systemctl is-active --quiet xray_tls; then
		echoColor green "✓ Xray TLS service restarted successfully!"
	else
		echoColor red "✗ Failed to restart service"
		systemctl status xray_tls
	fi
}

function regenerateClientConfig() {
	echoColor yellow "===== Regenerating Client Configuration ====="

	if [[ ! -f "$CONFIG_FILE" ]]; then
		echoColor red "Server config not found. Please install first."
		return 1
	fi

	local port=$(grep -oP '"port":\s*\K\d+' "$CONFIG_FILE" | head -1)
	local uuid=$(grep -oP '"id":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
	local domain=""

	if [[ -f "$DATA_DIR/connection_info.txt" ]]; then
		domain=$(grep -E "^Domain:" "$DATA_DIR/connection_info.txt" | head -1 | awk '{print $2}')
	fi

	if [[ -z "$domain" ]]; then
		read -p "$(echoColor yellow 'Enter domain for client config: ')" domain
	fi

	echoColor blue "Using values:"
	echoColor blue "  Domain: $domain"
	echoColor blue "  Port: $port"
	echoColor blue "  UUID: $uuid"

	if [[ -z "$domain" ]] || [[ -z "$port" ]] || [[ -z "$uuid" ]]; then
		echoColor red "Missing required values, cannot regenerate client config."
		return 1
	fi

	generateClientConfig "$domain" "$port" "$uuid"
}

function reissueCertificateInteractive() {
	echoColor yellow "===== Re-issue TLS Certificate (acme.sh) ====="

	local domain=""

	if [[ -f "$DATA_DIR/connection_info.txt" ]]; then
		domain=$(grep -E "^Domain:" "$DATA_DIR/connection_info.txt" | head -1 | awk '{print $2}')
	fi

	if [[ -z "$domain" ]]; then
		read -p "$(echoColor yellow 'Enter domain to re-issue certificate for: ')" domain
	fi

	if [[ -z "$domain" ]]; then
		echoColor red "Domain is empty, aborting."
		return 1
	fi

	issueCertificate "$domain"
	if [[ $? -eq 0 ]]; then
		echoColor green "Certificate re-issued successfully. Restarting Xray TLS..."
		systemctl restart xray_tls
	fi
}

function uninstallXray() {
	echoColor red "===== Uninstalling Xray TLS ====="
	read -p "Are you sure you want to uninstall? (yes/no): " confirm

	if [[ "$confirm" != "yes" ]]; then
		echoColor blue "Uninstall cancelled"
		return
	fi

	systemctl stop xray_tls
	systemctl disable xray_tls
	rm -f $SERVICE_FILE
	rm -f $BINARY_PATH
	rm -rf $CONFIG_DIR
	systemctl daemon-reload

	echoColor green "Xray TLS uninstalled (client config kept in $DATA_DIR)"
}

function showMenu() {
	clear
	echoColor green "======================================="
	echoColor green "   Xray TLS Manager v1.0"
	echoColor green "   (VLESS-TCP-XTLS-Vision)"
	echoColor green "======================================="
	echo ""

	if checkInstallation; then
		if systemctl is-active --quiet xray_tls; then
			echoColor green "Status: ✓ Installed & Running"
		else
			echoColor yellow "Status: Installed but Stopped"
		fi
	else
		echoColor red "Status: Not Installed"
	fi

	echo ""
	echoColor blue "  1. Install Xray TLS"
	echoColor blue "  2. Show Status & Config"
	echoColor blue "  3. Start Service"
	echoColor blue "  4. Stop Service"
	echoColor blue "  5. Restart Service"
	echoColor blue "  6. Update Xray Core"
	echoColor blue "  7. Show Connection Info"
	echoColor blue "  8. Uninstall"
	echoColor blue "  9. Regenerate Client Config"
	echoColor blue " 10. Re-issue TLS Certificate (acme.sh)"
	echoColor blue "  0. Exit"
	echo ""
}

while true; do
	showMenu
	read -t 6 -p "$(echoColor yellow 'Select option (default 1 in 6s): ')" choice
	choice=${choice:-1}

	case $choice in
	1)
		if checkInstallation; then
			echoColor yellow "Xray TLS is already installed!"
			read -t 6 -p "Reinstall? (yes/no, default yes in 6s): " confirm
			confirm=${confirm:-yes}
			if [[ "$confirm" == "yes" ]]; then
				DownloadxrayTlsCore
				installXrayTls
			fi
		else
			DownloadxrayTlsCore
			installXrayTls
		fi
		read -p "Press Enter to continue..."
		;;
	2)
		showStatus
		read -p "Press Enter to continue..."
		;;
	3)
		systemctl start xray_tls
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
		reissueCertificateInteractive
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
