#!/bin/bash

# Function to resolve domain to IP
resolve_domain_to_ip() {
  local domain="$1"
  ping -c 1 "$domain" | awk -F'[()]' '/PING/{print $2}'
}

# Function to get fraud score from Scamalytics
get_fraud_score() {
  local input="$1"
  local curl_output
  local fraud_score

  curl_output=$(curl -s "https://scamalytics.com/ip/${input}")
  fraud_score=$(echo "$curl_output" | perl -nle 'print $& if m{Fraud Score: (\d+)}')
  
  if [[ -n "$fraud_score" ]]; then
   #echo "Fraud Score: ${fraud_score}"
    echo "${fraud_score}"
  else
    echo "Fraud Score could not be determined."
  fi
}

# Ask for user input
echo -n "Enter an IP or domain: "
read input

# Initialize variables for output
ip=""
domain=""

# If no input is given, fetch the external IP
if [[ -z "$input" ]]; then
  ip=$(curl -s ifconfig.me)
else
  # Check if input is an IP or a domain using basic regex
  if [[ $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Input is an IP
    ip=$input
  else
    # Input is a domain, find its IP
    ip=$(resolve_domain_to_ip "$input")
    domain=$input
  fi
fi

# Fetch and parse IP information from ipinfo.io
ipinfo=$(curl -s "http://ipinfo.io/$ip")
hostname=$(echo "$ipinfo" | grep -oP '"hostname": "\K[^"]+')
timezone=$(echo "$ipinfo" | grep -oP '"timezone": "\K[^"]+')
loc=$(echo "$ipinfo" | grep -oP '"loc": "\K[^"]+')
region=$(echo "$ipinfo" | grep -oP '"region": "\K[^"]+')
city=$(echo "$ipinfo" | grep -oP '"city": "\K[^"]+')
country=$(echo "$ipinfo" | grep -oP '"country": "\K[^"]+')
org=$(echo "$ipinfo" | grep -oP '"org": "\K[^"]+')

# Display the results
echo "IP: $ip"
[[ -n "$domain" ]] && echo "Domain: $domain"
[[ -n "$hostname" ]] && echo "Hostname: $hostname"
[[ -n "$timezone" ]] && echo "Timezone: $timezone"
[[ -n "$loc" ]] && echo "Loc: $loc"
[[ -n "$region" ]] && echo "Region: $region"
[[ -n "$city" ]] && echo "City: $city"
[[ -n "$country" ]] && echo "Country: $country"
[[ -n "$org" ]] && echo "Org: $org"

# Display the fraud score
echo ""
get_fraud_score "$ip"
