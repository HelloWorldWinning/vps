
# Exit immediately if a command exits with a non-zero status
# set -e

# Define the unique ID
unique_id="install_1112_related_pre_tcpx_sh"

# Verify that unique_id is set
if [ -z "$unique_id" ]; then
    echo "Error: unique_id is empty."
    exit 1
fi

# Define the cron job line with the unique ID as a comment
# Using double quotes to allow variable expansion
cron_job="@reboot sleep 10 ; yes | bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pre_tcpx.sh )  #${unique_id}"

# Display the cron job being added
echo "Adding the following cron job to crontab:"
echo "$cron_job"

# Backup current crontab to a temporary file
temp_cron=$(mktemp)
crontab -l 2>/dev/null > "$temp_cron"

# Display the current crontab for debugging
echo "Current crontab contents:"
cat "$temp_cron"

# Check if the cron job already exists by searching for the unique ID
if grep -F "#${unique_id}" "$temp_cron" >/dev/null 2>&1; then
    echo "Cron job with ID '${unique_id}' already exists. No changes made."
else
    # Append the new cron job to the temporary crontab file
    echo "$cron_job" >> "$temp_cron"

    # Display the new crontab contents for debugging
    echo "Updated crontab contents:"
    cat "$temp_cron"

    # Install the new crontab
    crontab "$temp_cron"

    echo "Cron job added successfully."
fi

# Clean up the temporary file
rm "$temp_cron"

