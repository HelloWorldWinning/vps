#!/bin/bash

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

  # Method 1: Try with user agent and headers to bypass bot detection
  curl_output=$(curl -s \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Connection: keep-alive" \
    -H "Upgrade-Insecure-Requests: 1" \
    "https://scamalytics.com/ip/${input}")
  
  # Check if we got the anti-bot page
  if echo "$curl_output" | grep -q "Automated Access Detected"; then
    echo "Bot detection triggered - consider using their API"
    return
  fi
  
  # Try different regex patterns for fraud score extraction
  fraud_score=$(echo "$curl_output" | perl -nle 'print $1 if /Fraud Score:\s*(\d+)/')
  
  if [[ -z "$fraud_score" ]]; then
    # Try alternative patterns
    fraud_score=$(echo "$curl_output" | grep -oP 'Fraud Score[:\s]+\K\d+' | head -1)
  fi
  
  if [[ -z "$fraud_score" ]]; then
    # Try another pattern
    fraud_score=$(echo "$curl_output" | sed -n 's/.*Fraud Score[^0-9]*\([0-9]\+\).*/\1/p' | head -1)
  fi

  if [[ -n "$fraud_score" ]]; then
    echo "${fraud_score}"
  else
    echo "Fraud Score could not be determined (site may be blocking automated requests)"
  fi
}

# Alternative function using a different fraud checking service
get_fraud_score_alternative() {
  local input="$1"
  local curl_output
  
  # Try AbuseIPDB (requires free API key)
  # You can get a free API key from https://www.abuseipdb.com/api
  # Uncomment and add your API key:
  # API_KEY="your_api_key_here"
  # curl_output=$(curl -s -G https://api.abuseipdb.com/api/v2/check \
  #   --data-urlencode "ipAddress=$input" \
  #   -H "Key: $API_KEY" \
  #   -H "Accept: application/json")
  # confidence=$(echo "$curl_output" | jq -r '.data.abuseConfidenceScore // "N/A"')
  # echo "Abuse Confidence: $confidence%"
  
  # For now, just indicate alternative needed
  echo "Consider using AbuseIPDB or VirusTotal API for fraud checking"
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

output+="IP        : $ip\n"
[[ -n "$domain" ]] && output+="Domain    : $domain\n"
[[ -n "$hostname" ]] && output+="Hostname  : $hostname\n"
[[ -n "$timezone" ]] && output+="Timezone  : $timezone\n"
[[ -n "$region" ]] && output+="Region    : $region\n"
[[ -n "$city" ]] && output+="City      : $city\n"
output+="-------------------------------\n"
[[ -n "$org" ]] && output+="Org       : $org\n"
[[ -n "$country" ]] && output+="Country   : $country\n"

fraud_score=$(get_fraud_score "$ip")
output+="\nFraudScore: $fraud_score"

echo -e "$output"

echo "----------------------------------------------------------------------"
