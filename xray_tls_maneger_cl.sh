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
CERT_DIR="/etc/ssl/xray"
ACME_HOME="$HOME/.acme.sh"

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

#function DownloadxrayTLSCore() {
#	echoColor blue "Fetching latest Xray version..."
#	version=$(wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
#
#	if [[ -z "$version" ]]; then
#		echoColor red "Failed to fetch version information"
#		return 1
#	fi
#
#	echoColor green "Latest version: $version"
#
#	get_arch=$(arch)
#	temp_f=$(mktemp)
#	temp_d=$(mktemp -d)
#
#	echoColor blue "Downloading Xray core..."
#
#	if [ "$get_arch" = "x86_64" ]; then
#		wget -q -O $temp_f --no-check-certificate "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-64.zip"
#	elif [ "$get_arch" = "aarch64" ]; then
#		wget -q -O $temp_f --no-check-certificate "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-arm64-v8a.zip"
#	else
#		echoColor red "Unsupported architecture: $get_arch"
#		return 1
#	fi
#
#	unzip -q $temp_f -d $temp_d/
#
#	# FIX: Move binary AND geoip/geosite files
#	mv -f $temp_d/xray $BINARY_PATH
#	mv -f $temp_d/geoip.dat /usr/bin/geoip.dat
#	mv -f $temp_d/geosite.dat /usr/bin/geosite.dat
#	mv -f $temp_d/* /usr/bin/
#
#	chmod 755 $BINARY_PATH
#
#	rm -rf $temp_f $temp_d
#
#	echoColor green "Xray core and resource files downloaded successfully!"
#	$BINARY_PATH version
#}
function DownloadxrayTLSCore() {
	echoColor blue "Fetching latest Xray version..."
	version=$(curl -fsSL -m 5 "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')

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
		curl -fsSL -o $temp_f "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-64.zip"
	elif [ "$get_arch" = "aarch64" ]; then
		curl -fsSL -o $temp_f "https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-arm64-v8a.zip"
	else
		echoColor red "Unsupported architecture: $get_arch"
		return 1
	fi

	unzip -q $temp_f -d $temp_d/

	# FIX: Move binary AND geoip/geosite files
	mv -f $temp_d/xray $BINARY_PATH
	mv -f $temp_d/geoip.dat /usr/bin/geoip.dat
	mv -f $temp_d/geosite.dat /usr/bin/geosite.dat
	mv -f $temp_d/* /usr/bin/

	chmod 755 $BINARY_PATH

	rm -rf $temp_f $temp_d

	echoColor green "Xray core and resource files downloaded successfully!"
	$BINARY_PATH version
}

function installAcme() {
	echoColor blue "Installing acme.sh..."

	if [[ -f "$ACME_HOME/acme.sh" ]]; then
		echoColor green "acme.sh is already installed"
		return 0
	fi

	curl -s https://get.acme.sh | sh -s email=admin@example.com

	if [[ -f "$ACME_HOME/acme.sh" ]]; then
		echoColor green "acme.sh installed successfully!"
		return 0
	else
		echoColor red "Failed to install acme.sh"
		return 1
	fi
}

function issueCertificate() {
	local domain=$1

	if [[ -z "$domain" ]]; then
		echoColor red "Domain is required!"
		return 1
	fi

	echoColor blue "Issuing certificate for: $domain"

	# Create cert directory
	mkdir -p "$CERT_DIR"

	# Check if port 80 is in use
	if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
		echoColor red "Port 80 is in use! Please free port 80 first."
		echoColor yellow "You can temporarily stop the service using port 80"
		return 1
	fi

	# Issue certificate using standalone mode (port 80)
	"$ACME_HOME/acme.sh" --issue -d "$domain" --standalone --keylength ec-256 --force

	if [[ $? -ne 0 ]]; then
		echoColor red "Failed to issue certificate!"
		echoColor yellow "Make sure:"
		echoColor yellow "  1. Domain DNS points to this server"
		echoColor yellow "  2. Port 80 is accessible from internet"
		echoColor yellow "  3. No firewall blocking port 80"
		return 1
	fi

	# Install certificate to our directory
	"$ACME_HOME/acme.sh" --install-cert -d "$domain" --ecc \
		--fullchain-file "$CERT_DIR/fullchain.cer" \
		--key-file "$CERT_DIR/private.key" \
		--reloadcmd "systemctl restart xray_tls 2>/dev/null || true"

	if [[ -f "$CERT_DIR/fullchain.cer" ]] && [[ -f "$CERT_DIR/private.key" ]]; then
		chmod 644 "$CERT_DIR/fullchain.cer"
		chmod 600 "$CERT_DIR/private.key"
		echoColor green "Certificate installed successfully!"
		echoColor blue "  Certificate: $CERT_DIR/fullchain.cer"
		echoColor blue "  Private Key: $CERT_DIR/private.key"
		return 0
	else
		echoColor red "Failed to install certificate!"
		return 1
	fi
}

function renewCertificate() {
	echoColor blue "Renewing certificates..."

	"$ACME_HOME/acme.sh" --renew-all --ecc

	if [[ $? -eq 0 ]]; then
		echoColor green "Certificates renewed successfully!"
		systemctl restart xray_tls
	else
		echoColor yellow "No certificates need renewal or renewal failed"
	fi
}

function createSystemdService() {
	cat <<EOF >$SERVICE_FILE
[Unit]
Description=Xray TLS Service
Documentation=https://github.com/XTLS/xray-core/
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=$BINARY_PATH run -c $CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1000000
Environment="XRAY_LOCATION_ASSET=/usr/bin/"

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	echoColor green "Systemd service created!"
}

function installXrayTLS() {
	echoColor yellow "===== Installing Xray TLS (VLESS-TCP-XTLS-Vision) ====="

	apt update -y
	apt install -y wget curl unzip dnsutils net-tools socat cron

	# Install acme.sh
	installAcme
	if [[ $? -ne 0 ]]; then
		echoColor red "Failed to install acme.sh, aborting..."
		return 1
	fi

	# Get domain name (required for TLS)
	echo ""
	echoColor yellow "===== Domain Configuration ====="
	echoColor blue "A valid domain name is REQUIRED for TLS certificate"
	echoColor blue "Make sure DNS A record points to this server before proceeding!"
	echo ""
	read -p "$(echoColor yellow 'Enter your domain name: ')" DOMAIN

	if [[ -z "$DOMAIN" ]]; then
		echoColor red "Domain name is required for TLS!"
		return 1
	fi

	# Validate domain format
	if ! echo "$DOMAIN" | grep -qE "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"; then
		echoColor red "Invalid domain format!"
		return 1
	fi

	# FIX: Check existing certificate
	local NEED_ISSUE=true
	if [[ -f "$CERT_DIR/fullchain.cer" ]] && [[ -f "$CERT_DIR/private.key" ]]; then
		echo ""
		echoColor yellow "===== Existing Certificate Found ====="

		# Calculate days remaining
		local expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
		local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
		local now_epoch=$(date +%s)
		local days_left=$(((expiry_epoch - now_epoch) / 86400))

		echoColor blue "Certificate File: $CERT_DIR/fullchain.cer"
		if [[ $days_left -gt 0 ]]; then
			echoColor green "Validity: $days_left days remaining."
		else
			echoColor red "Validity: Expired ($days_left days)"
		fi

		echo ""
		echoColor yellow "Do you want to force re-issue the certificate?"
		echoColor yellow "Default: No (Reuse existing certificate) in 7 seconds."
		read -t 7 -p "Re-issue? [y/N]: " re_issue_choice

		if [[ "$re_issue_choice" == "y" ]] || [[ "$re_issue_choice" == "Y" ]]; then
			echoColor blue "User selected to re-issue certificate."
			NEED_ISSUE=true
		else
			echoColor green "Skipping certificate issuance. Using existing files."
			NEED_ISSUE=false
		fi
	fi

	if [[ "$NEED_ISSUE" == "true" ]]; then
		# Issue certificate
		echoColor blue "Issuing TLS certificate..."
		issueCertificate "$DOMAIN"
		if [[ $? -ne 0 ]]; then
			echoColor red "Failed to issue certificate, aborting..."
			return 1
		fi
	fi

	read -p "$(echoColor yellow 'Enter port (default 443, will auto-select in 8s): ')" -t 8 Port
	if [[ -z "$Port" ]]; then
		Port=443
		echoColor blue "Using default port: 443"
	fi

	# Ask for UUID generation method
	echo ""
	echoColor yellow "UUID Generation Options:"
	echoColor blue "  1. Use STATIC UUID (default)"
	echoColor blue "  2. Generate NEW random UUID"
	read -p "$(echoColor yellow 'Select option (default=1 in 6s): ')" -t 6 uuid_option

	if [[ -z "$uuid_option" ]] || [[ "$uuid_option" == "1" ]]; then
		# Use STATIC UUID
		echoColor green "Using STATIC UUID..."
		UUID="12345678-1234-1234-1234-123456789012"
		echoColor green "✓ Using STATIC UUID"
	else
		# Generate NEW UUID
		echoColor green "Generating NEW random UUID..."
		UUID=$($BINARY_PATH uuid 2>/dev/null)
		if [[ -z "$UUID" ]]; then
			UUID=$(cat /proc/sys/kernel/random/uuid)
		fi
		echoColor green "✓ Generated NEW UUID"
	fi

	echoColor blue "Getting public IP..."
	PUBLIC_IP=$(getPublicIP)

	if [[ -z "$PUBLIC_IP" ]]; then
		echoColor red "Failed to get public IP!"
		read -p "Please enter your server IP manually: " PUBLIC_IP
	fi

	echo ""
	echoColor yellow "===== Final Configuration ====="
	echoColor green "Domain: $DOMAIN"
	echoColor green "Server IP: $PUBLIC_IP"
	echoColor green "Port: $Port"
	echoColor green "UUID: $UUID"
	echoColor green "Certificate: $CERT_DIR/fullchain.cer"
	echoColor green "Private Key: $CERT_DIR/private.key"

	mkdir -p $CONFIG_DIR
	mkdir -p $DATA_DIR

	# Create server config for VLESS-TCP-XTLS-Vision with TLS
	cat <<EOF >$CONFIG_FILE
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "block"
      }
    ]
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
              "certificateFile": "$CERT_DIR/fullchain.cer",
              "keyFile": "$CERT_DIR/private.key"
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
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 2,
        "connIdle": 120
      }
    }
  }
}
EOF

	# Save domain info
	echo "$DOMAIN" >"$DATA_DIR/domain.txt"

	createSystemdService

	systemctl enable xray_tls
	systemctl start xray_tls

	sleep 2

	if systemctl is-active --quiet xray_tls; then
		echoColor green "✓ Xray TLS installed and started successfully!"
		generateClientConfig "$DOMAIN" "$PUBLIC_IP" "$Port" "$UUID"
	else
		echoColor red "✗ Failed to start Xray TLS service"
		echoColor yellow "Check logs with: journalctl -u xray_tls -e"
		systemctl status xray_tls
	fi
}

function generateClientConfig() {
	local domain=$1
	local ip=$2
	local port=$3
	local uuid=$4

	# Generate VLESS link (using domain for TLS)
	VLESS_LINK="vless://${uuid}@${domain}:${port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${domain}&fp=chrome&type=tcp&headerType=none#XrayTLS-${domain}"

	# Generate client JSON config
	CLIENT_JSON="$DATA_DIR/client_config.json"
	cat <<EOF >$CLIENT_JSON
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
          "tls",
          "quic"
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
EOF

	# Save connection info
	INFO_FILE="$DATA_DIR/connection_info.txt"
	cat <<EOF >$INFO_FILE
===== Xray TLS (VLESS-TCP-XTLS-Vision) Connection Information =====
Domain: $domain
Server IP: $ip
Port: $port
UUID: $uuid
Flow: xtls-rprx-vision
Security: tls
SNI: $domain
Fingerprint: chrome

===== Certificate Information =====
Certificate: $CERT_DIR/fullchain.cer
Private Key: $CERT_DIR/private.key
Auto-Renewal: Enabled via acme.sh cron

===== VLESS Link (Copy & Paste) =====
$VLESS_LINK

===== Client Config Files =====
JSON Config: $CLIENT_JSON
Connection Info: $INFO_FILE

===== Quick Copy =====
Server: $domain:$port
UUID: $uuid
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
	echoColor blue "- Certificate: $CERT_DIR/fullchain.cer"
	echoColor blue "- Private Key: $CERT_DIR/private.key"
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
		echoColor yellow "===== Certificate Status ====="
		if [[ -f "$CERT_DIR/fullchain.cer" ]]; then
			echoColor green "✓ Certificate exists"
			# Show certificate expiry
			local expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
			if [[ -n "$expiry" ]]; then
				echoColor blue "Expires: $expiry"
			fi
		else
			echoColor red "✗ Certificate not found"
		fi

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

	DownloadxrayTLSCore

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

	# Extract values from server config
	local port=$(grep -oP '"port":\s*\K\d+' "$CONFIG_FILE" | head -1)
	local uuid=$(grep -oP '"id":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)

	# Get domain from saved file or certificate
	local domain=""
	if [[ -f "$DATA_DIR/domain.txt" ]]; then
		domain=$(cat "$DATA_DIR/domain.txt")
	fi

	if [[ -z "$domain" ]] && [[ -f "$CERT_DIR/fullchain.cer" ]]; then
		domain=$(openssl x509 -noout -subject -in "$CERT_DIR/fullchain.cer" 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
	fi

	if [[ -z "$domain" ]]; then
		read -p "Enter domain name: " domain
	fi

	echoColor blue "Extracted from config:"
	echoColor blue "  Domain: $domain"
	echoColor blue "  Port: $port"
	echoColor blue "  UUID: $uuid"

	local public_ip=$(getPublicIP)
	if [[ -z "$public_ip" ]]; then
		read -p "Enter server IP: " public_ip
	fi

	generateClientConfig "$domain" "$public_ip" "$port" "$uuid"
}

function reissueCertificate() {
	echoColor yellow "===== Re-issue TLS Certificate ====="

	local domain=""
	if [[ -f "$DATA_DIR/domain.txt" ]]; then
		domain=$(cat "$DATA_DIR/domain.txt")
		echoColor blue "Current domain: $domain"
		read -p "Use this domain? (yes/no, default yes): " use_current
		if [[ "$use_current" == "no" ]]; then
			read -p "Enter new domain: " domain
		fi
	else
		read -p "Enter domain name: " domain
	fi

	if [[ -z "$domain" ]]; then
		echoColor red "Domain is required!"
		return 1
	fi

	# Stop service to free port if needed
	systemctl stop xray_tls 2>/dev/null

	# Issue certificate
	issueCertificate "$domain"

	if [[ $? -eq 0 ]]; then
		# Save domain
		echo "$domain" >"$DATA_DIR/domain.txt"

		# Update config file with new domain if needed
		if [[ -f "$CONFIG_FILE" ]]; then
			# Restart service
			systemctl start xray_tls

			if systemctl is-active --quiet xray_tls; then
				echoColor green "✓ Certificate re-issued and service restarted!"
				regenerateClientConfig
			else
				echoColor red "✗ Failed to restart service"
			fi
		fi
	else
		echoColor red "Failed to re-issue certificate"
		systemctl start xray_tls
	fi
}

function showCertificateInfo() {
	echoColor yellow "===== Certificate Information ====="

	if [[ ! -f "$CERT_DIR/fullchain.cer" ]]; then
		echoColor red "Certificate not found!"
		return 1
	fi

	echoColor blue "Certificate file: $CERT_DIR/fullchain.cer"
	echoColor blue "Private key file: $CERT_DIR/private.key"

	echo ""
	echoColor yellow "Certificate Details:"
	openssl x509 -noout -text -in "$CERT_DIR/fullchain.cer" | grep -A2 "Subject:" | head -3
	openssl x509 -noout -text -in "$CERT_DIR/fullchain.cer" | grep -A2 "Validity"

	echo ""
	local expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
	echoColor green "Expiry Date: $expiry"

	# Check if certificate is expiring soon
	local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
	local now_epoch=$(date +%s)
	local days_left=$(((expiry_epoch - now_epoch) / 86400))

	if [[ $days_left -lt 30 ]]; then
		echoColor red "⚠ Certificate expires in $days_left days! Consider renewing."
	else
		echoColor green "✓ Certificate valid for $days_left more days"
	fi

	echo ""
	echoColor yellow "acme.sh Certificates:"
	if [[ -f "$ACME_HOME/acme.sh" ]]; then
		"$ACME_HOME/acme.sh" --list
	else
		echoColor red "acme.sh not installed"
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
	rm -f /usr/bin/geoip.dat
	rm -f /usr/bin/geosite.dat
	rm -rf $CONFIG_DIR
	systemctl daemon-reload

	echoColor yellow "Remove certificates? (yes/no): "
	read -p "" remove_certs
	if [[ "$remove_certs" == "yes" ]]; then
		rm -rf $CERT_DIR
		echoColor green "Certificates removed"
	fi

	echoColor green "Xray TLS uninstalled (config backup kept in $DATA_DIR)"
}

function showMenu() {
	clear
	echoColor green "======================================="
	echoColor green "   Xray TLS Manager v1.1 (Fixed)"
	echoColor green "   (VLESS-TCP-XTLS-Vision)"
	echoColor green "======================================="
	echo ""

	if checkInstallation; then
		if systemctl is-active --quiet xray_tls; then
			echoColor green "Status: ✓ Installed & Running"
		else
			echoColor yellow "Status: Installed but Stopped"
		fi

		# Show certificate status
		if [[ -f "$CERT_DIR/fullchain.cer" ]]; then
			local expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
			local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
			local now_epoch=$(date +%s)
			local days_left=$(((expiry_epoch - now_epoch) / 86400))
			if [[ $days_left -lt 30 ]]; then
				echoColor red "Certificate: ⚠ Expires in $days_left days"
			else
				echoColor green "Certificate: ✓ Valid ($days_left days)"
			fi
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
	echoColor blue " 10. Re-issue Certificate"
	echoColor blue " 11. Renew Certificates"
	echoColor blue " 12. Show Certificate Info"
	echoColor blue "  0. Exit"
	echo ""
}

# Main loop
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
				DownloadxrayTLSCore
				installXrayTLS
			fi
		else
			DownloadxrayTLSCore
			installXrayTLS
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
		reissueCertificate
		read -p "Press Enter to continue..."
		;;
	11)
		renewCertificate
		read -p "Press Enter to continue..."
		;;
	12)
		showCertificateInfo
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
