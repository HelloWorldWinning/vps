# Update system packages and install Java Runtime Environment
apt update
apt install default-jre -y

# Create a directory for Tika and navigate to it
mkdir -p tika_d
cd tika_d

# Fetch the latest version of Apache Tika
tika_version_newest=$(curl -s https://dlcdn.apache.org/tika/ | grep -oP 'href="\K[0-9.]+(?=/")' | sort -V | tail -1)
echo "Latest Tika version: $tika_version_newest"

# Download the latest version of Tika server jar file
wget https://dlcdn.apache.org/tika/$tika_version_newest/tika-server-standard-$tika_version_newest.jar -O tika-server-standard_newest_version.jar

# Set up systemd service for Tika
cat <<EOF | sudo tee /etc/systemd/system/tika.service
[Unit]
Description=Apache Tika Server
After=network.target

[Service]
User=root
# Update the path below to the actual path where the Tika JAR is located
ExecStart=/usr/bin/java -jar $(pwd)/tika-server-standard_newest_version.jar -h 0.0.0.0 -p 9998

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start Tika service
sudo systemctl daemon-reload
sudo systemctl enable tika
sudo systemctl start tika

# Check the status of Tika service
sudo systemctl status tika -q

