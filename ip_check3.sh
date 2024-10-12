#!/bin/bash

#resolve_domain_to_ip() {
#  local domain="$1"
#  ping -c 1 "$domain" | awk -F'[()]' '/PING/{print $2}'
#}

resolve_domain_to_ip() {
  local input="$1"

  # Check if the input is a valid IPv4 or IPv6 address
  if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$input" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then
    echo "$input"
  else
    # Use dig to resolve the domain to an IP address
    dig +short "$input" | head -n 1
  fi
}




get_fraud_score() {
  local input="$1"
  local curl_output
  local fraud_score

  curl_output=$(curl -s "https://scamalytics.com/ip/${input}")
  fraud_score=$(echo "$curl_output" | perl -nle 'print $& if m{Fraud Score: (\d+)}')
    # Extract the last character, which is the numerical fraud score
  fraud_score=${fraud_score: -1}

  if [[ -n "$fraud_score" ]]; then
    echo "${fraud_score}"
  else
    echo "Fraud Score could not be determined."
  fi
}

echo -n "Enter an IP or domain: "
echo ""
read input

ip=""
domain=""
output=""

if [[ -z "$input" ]]; then
  ip=$(curl -s ifconfig.me)
else
  if [[ $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip=$input
  else
    ip=$(resolve_domain_to_ip "$input")
    domain=$input
  fi
fi



ipinfo=$(curl -s "http://ip-api.com/json/$ip?fields=country,regionName,city,timezone,org,reverse")

country=$(echo "$ipinfo" | jq -r '.country')
region=$(echo "$ipinfo" | jq -r '.regionName')
city=$(echo "$ipinfo" | jq -r '.city')
timezone=$(echo "$ipinfo" | jq -r '.timezone')
org=$(echo "$ipinfo" | jq -r '.org')
hostname=$(echo "$ipinfo" | jq -r '.reverse')

#ipinfo=$(curl -s "http://ipinfo.io/$ip?token=6d89f8e7f1a21e")
#hostname=$(echo "$ipinfo" | grep -oP '"hostname": "\K[^"]+')
#timezone=$(echo "$ipinfo" | grep -oP '"timezone": "\K[^"]+')
#loc=$(echo "$ipinfo" | grep -oP '"loc": "\K[^"]+')
#region=$(echo "$ipinfo" | grep -oP '"region": "\K[^"]+')
#city=$(echo "$ipinfo" | grep -oP '"city": "\K[^"]+')
#country=$(echo "$ipinfo" | grep -oP '"country": "\K[^"]+')
#org=$(echo "$ipinfo" | grep -oP '"org": "\K[^"]+')

output+="IP        : $ip\n"
[[ -n "$domain" ]] && output+="Domain    : $domain\n"
[[ -n "$hostname" ]] && output+="Hostname  : $hostname\n"
[[ -n "$timezone" ]] && output+="Timezone  : $timezone\n"
[[ -n "$loc" ]] && output+="Loc       : $loc\n"
[[ -n "$region" ]] && output+="Region    : $region\n"
[[ -n "$city" ]] && output+="City      : $city\n"
output+="-------------------------------\n"
[[ -n "$org" ]] && output+="Org       : $org\n"
[[ -n "$country" ]] && output+="Country   : $country\n"

fraud_score=$(get_fraud_score "$ip")
output+="\nFraudScore: $fraud_score"

echo -e "$output"

echo "----------------------------------------------------------------------"
