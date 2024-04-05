#!/bin/bash

# Define a list of services to get the public IP
services=(
  "https://api.ipify.org"
  "https://ipinfo.io/ip"
  "https://ifconfig.me"
)

# Function to get public IP using curl
get_public_ip() {
  for service in "${services[@]}"; do
    ip=$(curl -s "$service")
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo $ip
      return 0
    fi
  done

  echo "Failed to get public IP." >&2
  return 1
}

# Main function to execute the script
main() {
  public_ip=$(get_public_ip)
  if [[ -n $public_ip ]]; then
    echo "Public IP: $public_ip"
  else
    exit 1
  fi
}

# Execute the main function
main

