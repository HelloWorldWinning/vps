#!/bin/bash

# Create the token.service file
sudo tee /etc/systemd/system/token.service > /dev/null <<EOF
[Unit]
Description=Token Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$PWD
ExecStart=$(which python) $PWD/tokenizer_service.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload the systemd daemon
sudo systemctl daemon-reload

# Start the token service
sudo systemctl start token

# Enable the token service to start on system boot
sudo systemctl enable token

# Check the status of the token service
sudo systemctl status token
