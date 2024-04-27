#!/usr/bin/bash

# Get the hostname of the current machine
get_host_name=$(hostname)

echo "Starting setup on host: $get_host_name"

# Prompt for username and password
read -p "Enter username (leave empty for 1): " username
read -p "Enter password (leave empty for 1): " password
echo
       USERNAME=${username:-1}
       echo $USERNAME
       PASSWORD=${password:-1}
       echo $PASSWORD
