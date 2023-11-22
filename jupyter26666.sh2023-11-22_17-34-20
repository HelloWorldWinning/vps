
# number
echo "Enter the port number (default is 26666):"
read port

# If the user input is empty, use the default port number
if [ -z "$port" ]; then
  port=26666
fi

conda install python jupyter

# Find Python executable path
python_exec_path=$(which python)

# Ensure that the Python executable path was found
if [ -z "$python_exec_path" ]; then
    echo "Error: Python executable not found."
    exit 1
fi

# Create a systemd service file for Jupyter Notebook
service_name="jupyter${port}"
cat <<EOF | sudo tee /etc/systemd/system/${service_name}.service
[Unit]
Description=Jupyter Notebook

[Service]
Type=simple
ExecStart=$python_exec_path -m jupyter notebook --port=$port --ip=0.0.0.0 --no-browser --allow-root --notebook-dir=/
User=root
Environment="PATH=$(dirname $python_exec_path):${PATH}"

[Install]
WantedBy=multi-user.target
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

