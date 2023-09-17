# Identify the primary network interface (regardless of wg status)
PRIMARY_NETWORK_INTERFACE=$(ip -6 route | grep default | awk '{print $5}'|head -1)

echo $PRIMARY_NETWORK_INTERFACE

# Get all available IPv6 addresses for the interface
IPV6_ADDRESSES=$(ip -6 addr show $PRIMARY_NETWORK_INTERFACE | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+')

# Get the authentic public IPv6 by querying Cloudflare's DNS server using available IPv6 addresses
for IPV6_ADDRESS in $IPV6_ADDRESSES; do
  IPV6=$(dig @2606:4700:4700::1111 whoami.cloudflare ch txt +short -b $IPV6_ADDRESS | tr -d '"')
  if [ ! -z "$IPV6" ]; then
    break
  fi
done

echo $IPV6
