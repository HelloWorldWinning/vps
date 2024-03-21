#!/bin/bash

port=777
# Download the upload_folder.py script
wget -4 -O /root/upload_folder.py https://raw.githubusercontent.com/HelloWorldWinning/vps/main/upload_folder.py

#####sed -i 's/port=777/port=${port}/' /root/upload_folder.py
sed -i "s/port=777/port=${port}/" /root/upload_folder.py

# Install Flask and Werkzeug
pip install flask werkzeug

# Define the port number

# Define service name and log file path
service_name="upload${port}"
log_file="/var/log/${service_name}.log"

# Check if a Conda environment is active
if [ -z "$CONDA_DEFAULT_ENV" ]; then
    echo "Error: No active Conda environment found."
    exit 1
fi

# Capture the current Conda environment name
conda_env_name=$(echo $CONDA_DEFAULT_ENV)

# Determine the Conda setup script path
conda_setup_script="/root/anaconda3/etc/profile.d/conda.sh"

# Set the Conda environment's bin directory path
if [ "$conda_env_name" == "base" ]; then
    conda_env_bin_dir="/root/anaconda3/bin"
else
    conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"
fi

# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook Service on Port ${port}

[Service]
Type=simple
ExecStart=/bin/bash -c 'source $conda_setup_script; conda activate $conda_env_name; $conda_env_bin_dir/jupyter notebook --port=${port} --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/'
User=root
Environment="PATH=$conda_env_bin_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
StandardOutput=append:${log_file}
StandardError=append:${log_file}

[Install]
WantedBy=multi-user.target
EOF

# Create the log file and set appropriate permissions
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

