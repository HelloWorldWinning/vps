# Backup the original file
sudo cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup

# Comment out all existing SystemMaxUse and MaxRetentionSec lines
sudo sed -i 's/^SystemMaxUse=/#SystemMaxUse=/' /etc/systemd/journald.conf
sudo sed -i 's/^#*SystemMaxUse=/#SystemMaxUse=/' /etc/systemd/journald.conf
sudo sed -i 's/^MaxRetentionSec=/#MaxRetentionSec=/' /etc/systemd/journald.conf
sudo sed -i 's/^#*MaxRetentionSec=/#MaxRetentionSec=/' /etc/systemd/journald.conf

# Add our values at the end of the file
echo "SystemMaxUse=200M" | sudo tee -a /etc/systemd/journald.conf
echo "MaxRetentionSec=2week" | sudo tee -a /etc/systemd/journald.conf

# Verify
echo "=== New settings ==="
grep "^SystemMaxUse=" /etc/systemd/journald.conf
grep "^MaxRetentionSec=" /etc/systemd/journald.conf

# Restart and check
sudo systemctl restart systemd-journald
journalctl --disk-usage
