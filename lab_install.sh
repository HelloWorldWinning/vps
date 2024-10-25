#!/bin/bash

# Prompt for port number
echo "Enter the port number (default is 16666):"
read port

# If the user input is empty, use the default port number
if [ -z "$port" ]; then
  port=16666
fi
#

#conda install python jupyter    

conda install  -y  jupyter
conda  update -y  jupyter


service_name="jupyter${port}"
log_file="/var/log/${service_name}.log"
# Capture the current Conda environment name
conda_env_name=$(echo $CONDA_DEFAULT_ENV)

# Ensure that a Conda environment is active
if [ -z "$conda_env_name" ]; then
    echo "Error: No active Conda environment found."
    exit 1
fi

conda config --add channels defaults


# Find the path to the Conda setup script and the Conda environment's bin directory
conda_setup_script="/root/anaconda3/etc/profile.d/conda.sh"

python_path=$(which python)

# Check if the Python path contains 'miniconda3'
if [[ $python_path == *miniconda3* ]]; then
    # Set the path for Conda environment's bin directory to miniconda3
    conda_env_bin_dir="/root/miniconda3/bin"
    conda_setup_script="/root/miniconda3/etc/profile.d/conda.sh"
else
    # Set the path for Conda environment's bin directory based on the current environment
    if [ "$conda_env_name" == "base" ]; then
        conda_env_bin_dir="/root/anaconda3/bin"
    else
        conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"
    fi
fi
## Set the path for the Conda environment's bin directory
#if [ "$conda_env_name" == "base" ]; then
#    conda_env_bin_dir="/root/anaconda3/bin"
#else
#    conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"
#fi
#
# conda_env_bin_dir="/root/anaconda3/envs/$conda_env_name/bin"



# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook

[Service]
Type=simple
ExecStart=/bin/bash -c 'source $conda_setup_script; conda activate $conda_env_name; $conda_env_bin_dir/jupyter lab  --port=${port} --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/  --NotebookApp.contents_manager_class=jupyterlab_code_formatter.BlackContentsManager   --LabApp.default_url="/doc"    '
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


conda install -y cchardet chardet 
conda update -y nbconvert
$conda_env_bin_dir/pip install --upgrade nbconvert -y

conda install  -y notebook
conda update -y notebook

# Step 1: Install JupyterLab
conda install -c conda-forge jupyterlab -y
# Step 2: Update JupyterLab to the latest version
conda update -c conda-forge jupyterlab -y

###jupyter notebook password
###jupyter server password

curl -4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/lab_jupyter_server_config_json.txt  >  ~/.jupyter/jupyter_server_config.json



pip install chardet
conda update mistune -y

pip install   --upgrade nbconvert  jupyter isort   



######## black
# Install black formatter
pip install black 

# Install the JupyterLab code formatter extension
pip install jupyterlab-code-formatter 

# Enable the code formatter extension in JupyterLab
jupyter labextension install @ryantam626/jupyterlab_code_formatter

# Enable the Black formatter within JupyterLab
jupyter serverextension enable --py jupyterlab_code_formatter

# Configure JupyterLab Code Formatter to use Black as the default formatter
#jupyter lab --NotebookApp.contents_manager_class=jupyterlab_code_formatter.BlackContentsManager

######## black end



######## hidden  alll apprerance
# Script to configure JupyterLab sidebar settings
# This script should be run as root or with sudo

# Define the settings directory path
SETTINGS_DIR="/root/.jupyter/lab/user-settings/@jupyterlab/application-extension"

# Create the directory structure
echo "Creating directory structure..."
mkdir -p "$SETTINGS_DIR"

# Define the settings file path
SETTINGS_FILE="$SETTINGS_DIR/shell.jupyterlab-settings"

# Create the JSON configuration
echo "Creating configuration file..."
cat > "$SETTINGS_FILE" << 'EOF'
{
"interfaceStyle": "simple",
    "leftSideBar": {
        "visible": false
    },
    "rightSideBar": {
        "visible": false
    },
    "leftActivityBar": {
        "visible": false
    },
    "rightActivityBar": {
        "visible": false
    },
    "statusBar": {
        "visible": false
    }
}
EOF

# Set proper permissions
echo "Setting file permissions..."
chmod 644 "$SETTINGS_FILE"

# Verify the file was created
if [ -f "$SETTINGS_FILE" ]; then
    echo "Configuration successful!"
    echo "Settings file created at: $SETTINGS_FILE"
    echo "Please restart JupyterLab for changes to take effect."
else
    echo "Error: Failed to create settings file!"
    exit 1
fi

#########  format on save
mkdir -p $HOME/.jupyter
mkdir -p $HOME/.jupyter/lab
mkdir -p $HOME/.jupyter/lab/user-settings
mkdir -p $HOME/.jupyter/lab/user-settings/jupyterlab_code_formatter

cat <<"EOF" > $HOME/.jupyter/lab/user-settings/jupyterlab_code_formatter/settings.jupyterlab-settings
{
    "formatOnSave": true,
        "preferences": {
        "default_formatter": {
            "python":  ["black","isort"], 
            "R": "styler"
        }
    }
        
} 
EOF

#cat <<"EOF" > /root/.jupyter/lab/user-settings/jupyterlab_code_formatter/settings.jupyterlab-settings
#{
#    "formatOnSave": true,
#
#        "preferences": {
#        "default_formatter": {
#            "python":  ["black","isort"], 
#            "R": "styler"
#        }
#    }
#        
#} 
#EOF
#########  format on save end




######## hidden  alll apprerance   end

cat << "EOF" > ~/.jupyter/lab/user-settings/@jupyterlab/shortcuts-extension/shortcuts.jupyterlab-settings
{
    "shortcuts": [
        {
            "args": {},
            "command": "jupyterlab_code_formatter:black",
            "keys": [
                "Alt D"
            ],
            "selector": ".jp-Notebook.jp-mod-commandMode"
        },
        {
            "args": {},
            "command": "jupyterlab_code_formatter:black",
            "keys": [
                "Alt D"
            ],
            "selector": ".jp-Notebook.jp-mod-editMode"
        },
        {
            "args": {},
            "command": "jupyterlab_code_formatter:black",
            "keys": [
                "Alt D"
            ],
            "selector": ".jp-FileEditor"
        }
    ]
}
EOF









# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable $service_name

# Start the service immediately
sudo systemctl start $service_name

# Display the status of the service
echo "Service status:"
sudo systemctl status $service_name | head -n 20




#
#
#cat <<"EOF"
#//////////////////////
#    //
#    // List of keyboard shortcuts:
#
#{
#    "shortcuts": [
#
#
#        {
#            "args": {},
#            "command": "jupyterlab_code_formatter:black",
#            "keys": [
#                "Accel Shift F"
#            ],
#            "selector": ".jp-Notebook.jp-mod-commandMode"
#        },
#        {
#            "args": {},
#            "command": "jupyterlab_code_formatter:black",
#            "keys": [
#                "Accel Shift F"
#            ],
#            "selector": ".jp-Notebook.jp-mod-editMode"
#        },
#        {
#            "args": {},
#            "command": "jupyterlab_code_formatter:black",
#            "keys": [
#                "Accel Shift F"
#            ],
#            "selector": ".jp-FileEditor"
#        }
#
#
#
#    ]
#}
#//////////////////////
#EOF
#



