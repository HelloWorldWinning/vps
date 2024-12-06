#!/bin/bash

# Prompt for port number
echo "Enter the port number (default is 16666):"
read -t 4  port

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

##ExecStart=/bin/bash -c 'source $conda_setup_script; conda activate $conda_env_name; $conda_env_bin_dir/jupyter lab  --port=${port} --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/  --NotebookApp.contents_manager_class=jupyterlab_code_formatter.BlackContentsManager   --LabApp.default_url="/doc"    '


# Create the systemd service file
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook

[Service]
Type=simple
ExecStart=/bin/bash -c 'source $conda_setup_script; conda activate $conda_env_name; $conda_env_bin_dir/jupyter lab  --port=${port} --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/  --LabApp.default_url="/doc"    '
User=root
Environment="PATH=$conda_env_bin_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
StandardOutput=append:${log_file}
StandardError=append:${log_file}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create log file and set permissions
sudo touch ${log_file}
sudo chmod 664 ${log_file}


$conda_env_bin_dir/pip install   nbconvert  chardet   isort  black    
$conda_env_bin_dir/pip install  --upgrade nbconvert  chardet    isort  black    jupyterlab
#pip install --upgrade jupyterlab


### jupyterlab
conda install -y cchardet chardet  notebook  mistune  nbconvert isort
conda update -y nbconvert notebook   mistune isort


#pip install jupyterlab-code-formatter
#
## Enable the extension in JupyterLab
#jupyter server extension enable jupyterlab_code_formatter


###jupyter notebook password
###jupyter server password




#jupyter labextension install @ryantam626/jupyterlab_code_formatter
#jupyter serverextension enable --py jupyterlab_code_formatter

# Install and enable the code formatter
$conda_env_bin_dir/pip install --upgrade jupyterlab_code_formatter

# Enable the server extension using the modern command
jupyter server extension enable jupyterlab_code_formatter

# Verify the installation
jupyter server extension list



# Configure JupyterLab Code Formatter to use Black as the default formatter
#jupyter lab --NotebookApp.contents_manager_class=jupyterlab_code_formatter.BlackContentsManager

######## black end



######## hidden  alll apprerance
# Script to configure JupyterLab sidebar settings
# This script should be run as root or with sudo

# Define the settings directory path
mkdir  -p ~/.jupyter
mkdir  -p ~/.jupyter/lab
mkdir  -p ~/.jupyter/lab/user-settings
mkdir  -p ~/.jupyter/lab/user-settings/@jupyterlab
mkdir  -p ~/.jupyter/lab/user-settings/@jupyterlab/application-extension


#########  format on save


mkdir -p   $HOME/.jupyter
mkdir -p   $HOME/.jupyter/lab
mkdir -p   $HOME/.jupyter/lab/user-settings
mkdir -p   $HOME/.jupyter/lab/user-settings/jupyterlab_code_formatter

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


######## hidden  alll apprerance   end

mkdir -p   ~/.jupyter
mkdir -p   ~/.jupyter/lab
mkdir -p   ~/.jupyter/lab/user-settings
mkdir -p   ~/.jupyter/lab/user-settings/@jupyterlab
mkdir -p   ~/.jupyter/lab/user-settings/@jupyterlab/shortcuts-extension

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
      "command": "application:toggle-side-tabbar",
      "keys": [
        "Accel Shift B"
      ],
      "selector": ".jp-FileEditor"
    },
{
    "command": "running:show-panel",
    "keys": [
        "Accel Shift B"
    ],
    "selector": "body",
    "disabled": true
},
    {
      "args": {},
      "command": "application:toggle-side-tabbar",
      "keys": [
        "Accel Shift B"
      ],
      "selector": "body"
    },
    {
      "args": {},
      "command": "notebook:hide-cell-outputs",
      "keys": [
        "O"
      ],
      "selector": ".jp-Notebook.jp-mod-commandMode:not(.jp-mod-readWrite) :focus"
    },
    {
      "args": {},
      "command": "notebook:show-cell-outputs",
      "keys": [
        "Shift O"
      ],
      "selector": ".jp-Notebook.jp-mod-commandMode:not(.jp-mod-readWrite) :focus"
    },
    {
    "command": "docmanager:rename",
    "keys": [
        "Accel Shift R"
    ],
    "selector": "body"
    }
  ]
}
EOF


#######  no 6 items




#!/bin/bash

# Exit on error
set -e

# Create necessary directories
# Function to safely remove directory
remove_workspace() {
    local dir="$HOME/.jupyter/lab/workspaces"
    
    if [ -d "$dir" ]; then
        rm -rv "$dir"
        echo "Directory $dir successfully removed"
    else
        echo "Directory $dir does not exist - skipping removal"
    fi
}

# Execute the function
remove_workspace

mkdir -p /root/.jupyter/lab/workspaces
mkdir -p /root/.jupyter/lab/user-settings/@jupyterlab/statusbar-extension

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create the workspace configuration
WORKSPACE_FILE="/root/.jupyter/lab/workspaces/default-37a8.jupyterlab-workspace"
log_message "Creating workspace configuration at ${WORKSPACE_FILE}"

cat > "${WORKSPACE_FILE}" << 'EOL'
{
    "data": {
        "layout-restorer:data": {
            "main": {
                "dock": {
                    "type": "tab-area",
                    "currentIndex": 0,
                    "widgets": ["notebook:Untitled.ipynb"]
                },
                "current": "notebook:Untitled.ipynb"
            },
            "down": {
                "size": 0,
                "widgets": []
            },
            "left": {
                "collapsed": true,
                "visible": false,
                "current": "filebrowser",
                "widgets": [
                    "filebrowser",
                    "running-sessions",
                    "@jupyterlab/toc:plugin",
                    "extensionmanager.main-view"
                ]
            },
            "right": {
                "collapsed": true,
                "visible": false,
                "current": "jp-property-inspector",
                "widgets": [
                    "jp-property-inspector",
                    "debugger-sidebar"
                ]
            },
            "relativeSizes": [0, 1, 0],
            "top": {
                "simpleVisibility": false
            }
        },
        "docmanager:recents": {
            "opened": [],
            "closed": []
        }
    },
    "metadata": {
        "id": "default"
    }
}
EOL

# Create the statusbar settings
mkdir -p  "$HOME/.jupyter/lab"
mkdir -p  "$HOME/.jupyter/lab/user-settings"
mkdir -p  "$HOME/.jupyter/lab/user-settings/@jupyterlab"
mkdir -p  "$HOME/.jupyter/lab/user-settings/@jupyterlab/statusbar-extension"
STATUSBAR_FILE="$HOME/.jupyter/lab/user-settings/@jupyterlab/statusbar-extension/plugin.jupyterlab-settings"
log_message "Creating statusbar settings at ${STATUSBAR_FILE}"

cat > "${STATUSBAR_FILE}" << 'EOL'
{
    // Status Bar
    // @jupyterlab/statusbar-extension:plugin
    // Status Bar settings.
    // **************************************
    // Status Bar Visibility
    // Whether to show status bar or not
    "visible": false
}
EOL

# Check if files were created successfully
if [ -f "${WORKSPACE_FILE}" ] && [ -f "${STATUSBAR_FILE}" ]; then
    log_message "Successfully created all configuration files"
else
    log_message "Error: Failed to create one or more configuration files"
    exit 1
fi

# Set appropriate permissions
chmod 644 "${WORKSPACE_FILE}" "${STATUSBAR_FILE}"

log_message "Configuration complete"
#######  no 6 items end 







curl -4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/lab_jupyter_server_config_json.txt  >  ~/.jupyter/jupyter_server_config.json




#pip install --upgrade jupyterlab





# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable $service_name

# Start the service immediately
sudo systemctl start $service_name

# Display the status of the service
echo "Service status:"
sudo systemctl status $service_name | head -n 20



