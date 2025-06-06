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

get_ipqualityscore_data() {
	local input="$1"
	local ipqs_data

	# Replace with your IPQualityScore API key
	API_ipqualityscore="qiDrd9HwzZ7CPlyaveUmS8GYx4egf9nh"

	if [[ -z "$API_ipqualityscore" || "$API_ipqualityscore" == "YOUR_API_KEY_HERE" ]]; then
		echo "IPQualityScore API key not set"
		return
	fi

	ipqs_data=$(curl -s "https://ipqualityscore.com/api/json/ip/$API_ipqualityscore/$input?strictness=1&allow_public_access_points=true&fast=false&mobile=true&lighter_penalties=false")

	# Check if API call was successful
	local success=$(echo "$ipqs_data" | jq -r '.success // false')
	if [[ "$success" != "true" ]]; then
		echo "IPQualityScore API Error: $(echo "$ipqs_data" | jq -r '.message // "Unknown error"')"
		return
	fi

	# Function to check and display field only if not N/A, null, or empty
	display_field() {
		local label="$1"
		local value="$2"
		if [[ -n "$value" && "$value" != "N/A" && "$value" != "null" && "$value" != "false" ]]; then
			printf "%-10s: %s\n" "$label" "$value"
		fi
	}

	# Extract ALL IPQualityScore data fields
	local fraud_score=$(echo "$ipqs_data" | jq -r '.fraud_score // empty')
	local abuse_velocity=$(echo "$ipqs_data" | jq -r '.abuse_velocity // empty')
	local bot_status=$(echo "$ipqs_data" | jq -r '.bot_status // empty')
	local recent_abuse=$(echo "$ipqs_data" | jq -r '.recent_abuse // empty')

	local proxy=$(echo "$ipqs_data" | jq -r '.proxy // empty')
	local vpn=$(echo "$ipqs_data" | jq -r '.vpn // empty')
	local tor=$(echo "$ipqs_data" | jq -r '.tor // empty')
	local active_vpn=$(echo "$ipqs_data" | jq -r '.active_vpn // empty')
	local active_proxy=$(echo "$ipqs_data" | jq -r '.active_proxy // empty')

	local malware_risk=$(echo "$ipqs_data" | jq -r '.malware_risk // empty')
	local phishing_risk=$(echo "$ipqs_data" | jq -r '.phishing_risk // empty')
	local suspicious_activity=$(echo "$ipqs_data" | jq -r '.suspicious_activity // empty')
	local honeypot=$(echo "$ipqs_data" | jq -r '.honeypot // empty')
	local leaked_credentials=$(echo "$ipqs_data" | jq -r '.leaked_credentials // empty')

	local country_code=$(echo "$ipqs_data" | jq -r '.country_code // empty')
	local region=$(echo "$ipqs_data" | jq -r '.region // empty')
	local city=$(echo "$ipqs_data" | jq -r '.city // empty')
	local timezone=$(echo "$ipqs_data" | jq -r '.timezone // empty')
	local latitude=$(echo "$ipqs_data" | jq -r '.latitude // empty')
	local longitude=$(echo "$ipqs_data" | jq -r '.longitude // empty')
	local zip_code=$(echo "$ipqs_data" | jq -r '.zip_code // empty')

	local isp=$(echo "$ipqs_data" | jq -r '.ISP // empty')
	local organization=$(echo "$ipqs_data" | jq -r '.organization // empty')
	local asn=$(echo "$ipqs_data" | jq -r '.ASN // empty')
	local host=$(echo "$ipqs_data" | jq -r '.host // empty')

	local connection_type=$(echo "$ipqs_data" | jq -r '.connection_type // empty')
	local mobile=$(echo "$ipqs_data" | jq -r '.mobile // empty')
	local residential=$(echo "$ipqs_data" | jq -r '.residential // empty')
	local is_crawler=$(echo "$ipqs_data" | jq -r '.is_crawler // empty')

	local operating_system=$(echo "$ipqs_data" | jq -r '.operating_system // empty')
	local browser=$(echo "$ipqs_data" | jq -r '.browser // empty')
	local device_brand=$(echo "$ipqs_data" | jq -r '.device_brand // empty')
	local device_model=$(echo "$ipqs_data" | jq -r '.device_model // empty')

	local request_id=$(echo "$ipqs_data" | jq -r '.request_id // empty')

	# Display all available fields in ip_check3.sh format (only non-empty/non-N/A values)
	echo "-------------------------------"
	echo "🎯 FRAUD & RISK:"
	[[ -n "$fraud_score" ]] && printf "%-10s: %s%%\n" "FraudScore" "$fraud_score"
	display_field "AbuseVel" "$abuse_velocity"
	[[ "$bot_status" == "true" ]] && display_field "Bot" "$bot_status"
	[[ "$recent_abuse" == "true" ]] && display_field "RecentAb" "$recent_abuse"

	echo "-------------------------------"
	echo "🔒 ANONYMIZATION:"
	[[ "$proxy" == "true" ]] && display_field "Proxy" "$proxy"
	[[ "$vpn" == "true" ]] && display_field "VPN" "$vpn"
	[[ "$tor" == "true" ]] && display_field "Tor" "$tor"
	[[ "$active_vpn" == "true" ]] && display_field "ActiveVPN" "$active_vpn"
	[[ "$active_proxy" == "true" ]] && display_field "ActivePrxy" "$active_proxy"

	echo "-------------------------------"
	echo "🛡️ SECURITY:"
	[[ "$malware_risk" == "true" ]] && display_field "Malware" "$malware_risk"
	[[ "$phishing_risk" == "true" ]] && display_field "Phishing" "$phishing_risk"
	[[ "$suspicious_activity" == "true" ]] && display_field "Suspicious" "$suspicious_activity"
	[[ "$honeypot" == "true" ]] && display_field "Honeypot" "$honeypot"
	[[ "$leaked_credentials" == "true" ]] && display_field "LeakedCred" "$leaked_credentials"

	echo "-------------------------------"
	echo "🌍 GEOGRAPHIC:"
	display_field "CountryC" "$country_code"
	display_field "Region" "$region"
	display_field "City" "$city"
	display_field "Timezone" "$timezone"
	display_field "Latitude" "$latitude"
	display_field "Longitude" "$longitude"
	display_field "ZipCode" "$zip_code"

	echo "-------------------------------"
	echo "🏢 NETWORK:"
	display_field "ISP" "$isp"
	display_field "Org" "$organization"
	display_field "ASN" "$asn"
	display_field "Host" "$host"

	echo "-------------------------------"
	echo "📱 CONNECTION:"
	display_field "ConnType" "$connection_type"
	[[ "$mobile" == "true" ]] && display_field "Mobile" "$mobile"
	[[ "$residential" == "true" ]] && display_field "Residential" "$residential"
	[[ "$is_crawler" == "true" ]] && display_field "Crawler" "$is_crawler"

	echo "-------------------------------"
	echo "💻 DEVICE:"
	display_field "OS" "$operating_system"
	display_field "Browser" "$browser"
	display_field "DevBrand" "$device_brand"
	display_field "DevModel" "$device_model"

	echo "-------------------------------"
	echo "📊 API INFO:"
	display_field "RequestID" "$request_id"
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

# Get IPQualityScore data instead of Scamalytics
ipqs_output=$(get_ipqualityscore_data "$ip")
output+="\n$ipqs_output"

echo -e "$output"

echo "----------------------------------------------------------------------"
