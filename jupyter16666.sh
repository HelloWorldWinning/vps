#!/bin/bash

# Prompt for port number
echo "Enter the port number (default is 16666):"
read port

# If the user input is empty, use the default port number
if [ -z "$port" ]; then
  port=16666
fi

# Install required packages
conda install -y jupyter
conda install -y notebook==6.5.4
###Could not solve for environment specs                                                                                             
###The following packages are incompatible                                                                                            
###├─ notebook 6.5.4  is installable with the potential options                                                                       
###│  ├─ notebook 6.5.4 would require                                                                                                 
###│  │  └─ python >=3.10,<3.11.0a0 , which can be installed;                                                                         
###│  ├─ notebook 6.5.4 would require                                                                                                 
###│  │  └─ python >=3.11,<3.12.0a0 , which can be installed;   


conda config --add channels defaults

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

# Find the Conda base directory and setup script
python_path=$(which python)
if [[ $python_path == *miniconda3* ]]; then
    conda_base="/root/miniconda3"
else
    conda_base="/root/anaconda3"
fi
conda_setup_script="${conda_base}/etc/profile.d/conda.sh"

# Determine the correct jupyter executable path within the active environment
if [ "$conda_env_name" == "base" ]; then
    jupyter_path="${conda_base}/bin/jupyter"
    conda_env_bin_dir="${conda_base}/bin"
else
    jupyter_path="${conda_base}/envs/${conda_env_name}/bin/jupyter"
    conda_env_bin_dir="${conda_base}/envs/${conda_env_name}/bin"
fi

# Verify jupyter executable exists
if [ ! -f "$jupyter_path" ]; then
    echo "Warning: Jupyter not found in environment path. Installing in current environment..."
    conda install -y jupyter
    # Update jupyter_path after installation
    jupyter_path=$(which jupyter)
fi

# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook

[Service]
Type=simple
ExecStart=/bin/bash -c 'source ${conda_setup_script}; conda activate ${conda_env_name}; ${jupyter_path} notebook --port=${port} --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/'
User=root
Environment="PATH=${conda_env_bin_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
StandardOutput=append:${log_file}
StandardError=append:${log_file}

[Install]
WantedBy=multi-user.target
EOF

# Create log file and set permissions
sudo touch ${log_file}
sudo chmod 664 ${log_file}

# Install additional packages
conda install -y -c conda-forge cchardet chardet 
conda install -y -c conda-forge notebook==6.5.4

conda update -y nbconvert
${conda_env_bin_dir}/pip install --upgrade nbconvert

jupyter notebook password

pip install chardet
conda update -y mistune
pip install --upgrade nbconvert jupyter

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable $service_name

# Start the service immediately
sudo systemctl start $service_name

# Display the status of the service
echo "Service status:"
sudo systemctl status $service_name | head -n 20
