#!/bin/bash

# Create organized directory structure for VPN tools
VPN_BASE_DIR="/data/d.share/vpn-tools"
OPENVPN_DIR="$VPN_BASE_DIR/openvpn"
WIREGUARD_DIR="$VPN_BASE_DIR/wireguard"

# Create directories if they don't exist
mkdir -p "$OPENVPN_DIR"
mkdir -p "$WIREGUARD_DIR"

echo "Downloading VPN tools to organized directories..."
echo "Base directory: $VPN_BASE_DIR"

# Download OpenVPN files
echo "Downloading OpenVPN files..."
wget -4 -P "$OPENVPN_DIR" https://openvpn.net/downloads/openvpn-connect-v3-windows.msi
wget -4 -P "$OPENVPN_DIR" https://github.com/HelloWorldWinning/vps/raw/refs/heads/main/backup_D/net.openvpn.openvpn_3.7.1.apk

# Download WireGuard files
echo "Downloading WireGuard files..."

# Get the latest WireGuard APK URL dynamically
echo "Fetching latest WireGuard APK URL..."
WG_HTML=$(curl -s https://download.wireguard.com/android-client/)
WG_APK_NAME=$(echo "$WG_HTML" | grep -o 'com\.wireguard\.android-[0-9]\+\.[0-9]\+\.[0-9]\+\.apk' | head -1)

if [ -n "$WG_APK_NAME" ]; then
	echo "Latest WireGuard APK: $WG_APK_NAME"
	wget -4 -P "$WIREGUARD_DIR" "https://download.wireguard.com/android-client/$WG_APK_NAME"
else
	echo "Failed to get latest WireGuard APK URL, using fallback..."
	wget -4 -P "$WIREGUARD_DIR" https://download.wireguard.com/android-client/com.wireguard.android-1.0.20250531.apk
fi

wget -4 -P "$WIREGUARD_DIR" https://github.com/HelloWorldWinning/vps/raw/refs/heads/main/backup_D/wireguard-export2025-08-18_10.zip

echo "Download completed!"
echo "Files organized in:"
echo "  OpenVPN: $OPENVPN_DIR"
echo "  WireGuard: $WIREGUARD_DIR"

mkdir -p /root/wg_clients
unzip /data/d.share/vpn-tools/wireguard/wireguard-export2025-08-18_10.zip -d /root/wg_clients
mv /data/d.share/vpn-tools/wireguard/wireguard-export2025-08-18_10.zip /root/wg_clients/

# Optional: List downloaded files
echo ""
echo "Downloaded files:"
echo "OpenVPN files:"
ls -la "$OPENVPN_DIR"
echo ""
echo "WireGuard files:"
ls -la "$WIREGUARD_DIR"





# Install qrencode if not already installed
sudo apt install qrencode -y

# Define the QR PNG output directory
qr_png_path="/root/wg_clients/qr_d/"

# Create the output directory if it doesn't exist
mkdir -p "$qr_png_path"

# Process each file matching the pattern "00_dd_*"
# Using find to properly handle filenames with spaces
find /root/wg_clients -maxdepth 1 -name "00_dd_*" -type f | while IFS= read -r file_path; do
	# Extract just the filename from the full path
	filename=$(basename "$file_path")

	# Create QR code PNG file
	qrencode -t PNG -o "${qr_png_path}${filename}.png" -r "$file_path"

	echo "Generated QR code: ${qr_png_path}${filename}.png"
done

echo "QR code generation complete!"
