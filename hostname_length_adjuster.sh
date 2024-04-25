#!/bin/bash

# Path to your JSON configuration
config_path="/root/themes/gmay3.omp.json"

# Get the actual hostname to calculate its length
hostname=$(hostname)
hostname_length=${#hostname}

# Generate a string of spaces equal to the length of the hostname
spaces=$(printf '%*s' $hostname_length)

# Update the template in the JSON file
# This requires jq - a command-line JSON processor
# \u2B95  \u2B95
jq '.blocks[1].segments[0].template = "'"$spaces   \u27A4"'"' $config_path > temp.json && mv temp.json $config_path

# Now you can initialize Oh-My-Posh
eval "$(oh-my-posh init bash --config $config_path)"
