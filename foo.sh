# Function to resolve domain to IP address
resolve_domain_to_ip() {
  local domain="$1"
  local ip_address=$(dig +short "$domain")
  if [[ -n "$ip_address" ]]; then
    echo "$ip_address"
  else
    echo "Failed to resolve IP for domain $domain."
    return 1
  fi
}

# Function to get the fraud score
get_fraud_score() {
  local input="$1"
  local curl_output
  local fraud_score
  local ip_address

  if [[ -z "$input" ]]; then
    ip_address=$(curl -s ifconfig.me)
  elif [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip_address="$input"
  else
    ip_address=$(resolve_domain_to_ip "$input")
    if [[ $? -ne 0 ]]; then
      echo "Failed to resolve domain to IP."
      return 1
    fi
  fi

  curl_output=$(curl -s "https://scamalytics.com/ip/${ip_address}")
  fraud_score=$(echo "$curl_output" | perl -nle 'print $& if m{Fraud Score: (\d+)}')

  if [[ -n "$fraud_score" ]]; then
    echo "IP: ${ip_address}"
    echo "Fraud Score: ${fraud_score}"
  else
    echo "Fraud Score could not be determined."
  fi
}

get_fraud_score
