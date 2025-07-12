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

get_abuseipdb_data() {
	local input="$1"
	local abuseipdb_data

	# AbuseIPDB API key
	API_KEY="0889e1ce519207cc34b2f0f19aeee2060ccf5d165b21f6ab543cb9202c76ef6968eea6025d2e38a1"

	if [[ -z "$API_KEY" || "$API_KEY" == "YOUR_API_KEY_HERE" ]]; then
		echo "AbuseIPDB API key not set"
		return
	fi

	abuseipdb_data=$(curl -sG https://api.abuseipdb.com/api/v2/check \
		--data-urlencode "ipAddress=$input" \
		--data-urlencode "maxAgeInDays=90" \
		-H "Key: $API_KEY" \
		-H "Accept: application/json")

	# Check if API call was successful
	if [[ -z "$abuseipdb_data" ]] || [[ "$abuseipdb_data" == *"error"* ]]; then
		echo "AbuseIPDB API Error: Unable to fetch data"
		return
	fi

	# Function to check and display field only if not N/A, null, empty, or false
	display_field() {
		local label="$1"
		local value="$2"
		if [[ -n "$value" && "$value" != "N/A" && "$value" != "null" && "$value" != "false" && "$value" != "[]" ]]; then
			printf "%-10s: %s\n" "$label" "$value"
		fi
	}

	# Extract AbuseIPDB data fields
	local ip_address=$(echo "$abuseipdb_data" | jq -r '.data.ipAddress // empty')
	local is_public=$(echo "$abuseipdb_data" | jq -r '.data.isPublic // empty')
	local ip_version=$(echo "$abuseipdb_data" | jq -r '.data.ipVersion // empty')
	local is_whitelisted=$(echo "$abuseipdb_data" | jq -r '.data.isWhitelisted // empty')
	local abuse_confidence_score=$(echo "$abuseipdb_data" | jq -r '.data.abuseConfidenceScore // empty')
	local country_code=$(echo "$abuseipdb_data" | jq -r '.data.countryCode // empty')
	local usage_type=$(echo "$abuseipdb_data" | jq -r '.data.usageType // empty')
	local isp=$(echo "$abuseipdb_data" | jq -r '.data.isp // empty')
	local domain=$(echo "$abuseipdb_data" | jq -r '.data.domain // empty')
	local hostnames=$(echo "$abuseipdb_data" | jq -r '.data.hostnames | join(", ") // empty')
	local is_tor=$(echo "$abuseipdb_data" | jq -r '.data.isTor // empty')
	local total_reports=$(echo "$abuseipdb_data" | jq -r '.data.totalReports // empty')
	local num_distinct_users=$(echo "$abuseipdb_data" | jq -r '.data.numDistinctUsers // empty')
	local last_reported_at=$(echo "$abuseipdb_data" | jq -r '.data.lastReportedAt // empty')

	# Display all available fields in organized format
	echo "-------------------------------"
	echo "🎯 ABUSE & REPUTATION:"
	[[ -n "$abuse_confidence_score" ]] && printf "%-10s: %s%%\n" "AbuseScore" "$abuse_confidence_score"
	[[ -n "$total_reports" && "$total_reports" != "0" ]] && display_field "Reports" "$total_reports"
	[[ -n "$num_distinct_users" && "$num_distinct_users" != "0" ]] && display_field "Reporters" "$num_distinct_users"
	display_field "LastReport" "$last_reported_at"

	echo "-------------------------------"
	echo "🔒 ANONYMIZATION:"
	[[ "$is_tor" == "true" ]] && display_field "Tor" "$is_tor"
	display_field "UsageType" "$usage_type"

	echo "-------------------------------"
	echo "🌍 GEOGRAPHIC:"
	display_field "CountryC" "$country_code"

	echo "-------------------------------"
	echo "🏢 NETWORK:"
	display_field "ISP" "$isp"
	display_field "Domain" "$domain"
	display_field "Hostnames" "$hostnames"

	echo "-------------------------------"
	echo "📊 IP INFO:"
	display_field "IP" "$ip_address"
	display_field "IPVersion" "$ip_version"
	[[ "$is_public" == "true" ]] && display_field "Public" "$is_public"
	[[ "$is_whitelisted" == "true" ]] && display_field "Whitelisted" "$is_whitelisted"
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
[[ -n "$loc" ]] && output+="Loc       : $loc\n"
[[ -n "$region" ]] && output+="Region    : $region\n"
[[ -n "$city" ]] && output+="City      : $city\n"
output+="-------------------------------\n"
[[ -n "$org" ]] && output+="Org       : $org\n"
[[ -n "$country" ]] && output+="Country   : $country\n"

# Get AbuseIPDB data
abuseipdb_output=$(get_abuseipdb_data "$ip")
output+="\n$abuseipdb_output"

# Extract AbuseScore for summary display
abuse_score_summary=""
if [[ -n "$abuseipdb_output" ]]; then
	abuse_score_summary=$(echo "$abuseipdb_output" | grep "AbuseScore:" | head -1)
fi

# Add separator and abuse score summary
if [[ -n "$abuse_score_summary" ]]; then
	output+="\n-------------------------------"
	output+="\n$abuse_score_summary"
fi

echo -e "$output"

echo "----------------------------------------------------------------------"
