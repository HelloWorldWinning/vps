#!/bin/bash

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
