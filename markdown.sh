#!/usr/bin/bash

# Create the necessary directory
mkdir -p /data/trend_trading2/555.d/

# Download the Python script to the specified location
wget -4 -O /data/trend_trading2/555.d/markdown_render_flask3.py  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/markdown_render_flask3.py

######

service_name="markdown"
log_file="/var/log/${service_name}.log"

# Capture the current Conda environment name
conda_env_name=$(echo $CONDA_DEFAULT_ENV)

# Ensure that a Conda environment is active
if [ -z "$conda_env_name" ]; then
    echo "Error: No active Conda environment found."
    exit 1
fi

# Find the path to the Conda setup script
conda_setup_script="/root/anaconda3/etc/profile.d/conda.sh"

# Set the path for the Conda environment's bin directory
if [ "$conda_env_name" == "base" ]; then
    conda_env_bin_dir="/root/anaconda3/bin"
else
    conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"
fi

# Install required Python packages for markdown_render_flask3.py
#conda_env_bin_dir/
pip install flask markdown2 flask_httpauth



# Determine the correct Python path
python_path=$(which python)

# Check if the Python path contains 'miniconda3'
if [[ $python_path == *miniconda3* ]]; then
    # Set the path for Conda environment's bin directory to miniconda3
    conda_env_bin_dir="/root/miniconda3/bin"
else
    # Set the path for Conda environment's bin directory based on the current environment
    if [ "$conda_env_name" == "base" ]; then
        conda_env_bin_dir="/root/anaconda3/bin"
    else
        conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"
    fi
fi



# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Markdown Render Flask Service

[Service]
Type=simple
ExecStart=$conda_env_bin_dir/python /data/trend_trading2/555.d/markdown_render_flask3.py
User=root
StandardOutput=append:${log_file}
StandardError=append:${log_file}

[Install]
WantedBy=multi-user.target
EOF

# Create log file and set permissions
sudo touch ${log_file}
sudo chmod 664 ${log_file}

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable $service_name

# Start the service immediately
sudo systemctl start $service_name

# Display the status of the service
echo "Service status:"
sudo systemctl status $service_name | head -n 20


