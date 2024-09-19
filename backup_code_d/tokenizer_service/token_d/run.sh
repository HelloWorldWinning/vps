#!/bin/bash

# Get the path of the python executable
python_path=$(which python3)

# Check if python was not found
if [ -z "$python_path" ]; then
  echo "Python3 was not found on your system."
  exit 1
fi

# Get current path
current_path=$(pwd)

# Get the name of the current Conda environment; it is assumed to be the current shell's active environment
conda_env=$(conda info --json | jq -r '.active_prefix_name')

# Check if the conda_env variable is empty, which means no Conda environment is active
if [ -z "$conda_env" ]; then
  echo "No active Conda environment found. Please activate the required environment before running this script."
  exit 1
fi

# Get the path to the conda sh file
conda_path=$(conda info --base)
conda_sh="$conda_path/etc/profile.d/conda.sh"

# Create systemd service file
sudo tee /etc/systemd/system/token_counter.service > /dev/null << EOF
[Unit]
Description=OpenAI Coze service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'source $conda_sh && conda activate $conda_env && $python_path token_counter.py'
WorkingDirectory=$current_path
Restart=always
User=root
Group=root
Environment=PYTHONUNBUFFERED=1
StandardOutput=append:/var/log/token_counter.log
StandardError=append:/var/log/token_counter.log

[Install]
WantedBy=multi-user.target
EOF

sudo touch /var/log/token_counter.log
sudo chmod 664 /var/log/token_counter.log

# Reload systemd manager configuration
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable token_counter.service

# Stop the service if it's running
sudo systemctl stop token_counter.service

## Test the ExecStart command directly
#echo "Testing ExecStart command..."
#cd $current_path && /bin/bash -c 'source $conda_sh && conda activate $conda_env && $python_path token_counter.py'

# Start the service
echo "Starting the service..."
sudo systemctl start token_counter.service

# Check the service status
systemctl status token_counter.service

# Print the last 20 lines of the log file
echo "Last 20 lines of the log file:"
tail -n 20 /var/log/token_counter.log

