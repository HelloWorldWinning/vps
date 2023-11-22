#!/bin/bash

# Prompt for port number
echo "Enter the port number (default is 26666):"
read port

# If the user input is empty, use the default port number
if [ -z "$port" ]; then
  port=26666
fi
#

#conda install python jupyter    
conda install jupyter
conda install notebook==6.5.4

# Create a systemd service file for Jupyter Notebook with dynamic Conda environment activation and logging
service_name="jupyter${port}"
log_file="/var/log/${service_name}.log"
# Capture the current Conda environment name
conda_env_name=$(echo $CONDA_DEFAULT_ENV)

# Ensure that a Conda environment is active
if [ -z "$conda_env_name" ]; then
    echo "Error: No active Conda environment found."
    exit 1
fi

# Find the path to the Conda setup script and the Conda environment's bin directory
conda_setup_script="/root/anaconda3/etc/profile.d/conda.sh"
conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"



# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook

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

