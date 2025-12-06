#!/bin/bash
set -u

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# Base directories
BASE_DIR="/root/xray_xhttp3_d"
DATA_DIR="$BASE_DIR/data"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
CERT_DIR="$DATA_DIR/certs"
NGINX_CONF_DIR="$DATA_DIR/nginx"
XRAY_CONF_DIR="$DATA_DIR/xray"
CLIENT_DIR="$DATA_DIR/client"
ACME_HOME="$HOME/.acme.sh"

# Container names
NGINX_CONTAINER="xray_xhttp3_nginx"
XRAY_CONTAINER="xray_xhttp3_xray"

function echoColor() {
    case $1 in
    "red") echo -e "\033[31m$2\033[0m" ;;
    "green") echo -e "\033[32m$2\033[0m" ;;
    "yellow") echo -e "\033[33m$2\033[0m" ;;
    "blue") echo -e "\033[36m$2\033[0m" ;;
    "purple") echo -e "\033[1;35m$2\033[0m" ;;
    *) echo -e "$2" ;;
    esac
}

function checkInstallation() {
    if [[ -f "$COMPOSE_FILE" ]] && [[ -f "$XRAY_CONF_DIR/config.json" ]] && [[ -f "$NGINX_CONF_DIR/nginx.conf" ]]; then
        return 0
    else
        return 1
    fi
}

function checkDockerRunning() {
    if docker compose -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q "$XRAY_CONTAINER"; then
        return 0
    else
        return 1
    fi
}

function getPublicIP() {
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    IPV4=$(dig @1.1.1.1 whoami.cloudflare ch txt +short -b $(ip -4 addr show $PRIMARY_INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1) 2>/dev/null | tr -d '"')

    if [[ -z "$IPV4" ]]; then
        IPV4=$(curl -s -4 ifconfig.me 2>/dev/null)
    fi
    if [[ -z "$IPV4" ]]; then
        IPV4=$(curl -s -4 icanhazip.com 2>/dev/null)
    fi

    echo "$IPV4"
}

function checkDocker() {
    if ! command -v docker &>/dev/null; then
        echoColor red "Docker is not installed!"
        echoColor yellow "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        if ! command -v docker &>/dev/null; then
            echoColor red "Failed to install Docker!"
            return 1
        fi
        echoColor green "Docker installed successfully!"
    fi

    if ! docker compose version &>/dev/null; then
        echoColor red "Docker Compose V2 is not available!"
        echoColor yellow "Please update Docker to a recent version with Compose V2 support"
        return 1
    fi

    echoColor green "✓ Docker and Docker Compose V2 are available"
    return 0
}

function installAcme() {
    echoColor blue "Installing acme.sh..."
    if [[ -f "$ACME_HOME/acme.sh" ]]; then
        echoColor green "acme.sh is already installed"
        return 0
    fi
    curl -s https://get.acme.sh | sh -s email=admin@example.com
    if [[ -f "$ACME_HOME/acme.sh" ]]; then
        echoColor green "acme.sh installed successfully!"
        return 0
    else
        echoColor red "Failed to install acme.sh"
        return 1
    fi
}

# [FIX] Check if certificate exists and is valid (not expired)
function checkCertificateValid() {
    local domain=$1
    if [[ ! -f "$CERT_DIR/fullchain.cer" ]] || [[ ! -f "$CERT_DIR/private.key" ]]; then
        return 1
    fi
    
    # Check if certificate is expired or expiring within 7 days
    local expiry_epoch
    expiry_epoch=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
    if [[ -z "$expiry_epoch" ]]; then
        return 1
    fi
    
    local expiry_ts
    expiry_ts=$(date -d "$expiry_epoch" +%s 2>/dev/null)
    local now_ts
    now_ts=$(date +%s)
    local days_left=$(((expiry_ts - now_ts) / 86400))
    
    if [[ $days_left -lt 7 ]]; then
        echoColor yellow "Certificate expires in $days_left days, should renew"
        return 1
    fi
    
    # Optionally check if domain matches (basic check)
    if [[ -n "$domain" ]]; then
        local cert_domain
        cert_domain=$(openssl x509 -noout -subject -in "$CERT_DIR/fullchain.cer" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
        if [[ "$cert_domain" != "$domain" ]]; then
            echoColor yellow "Certificate domain ($cert_domain) doesn't match requested domain ($domain)"
            return 1
        fi
    fi
    
    return 0
}

function issueCertificate() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        echoColor red "Domain is required!"
        return 1
    fi

    echoColor blue "Issuing certificate for: $domain"
    mkdir -p "$CERT_DIR"

    # stop containers to free :80 if running
    if [[ -f "$COMPOSE_FILE" ]]; then
        docker compose -f "$COMPOSE_FILE" down 2>/dev/null
    fi

    # Check if port 80 is in use
    if ss -lntp 2>/dev/null | grep -qE 'LISTEN.+:80\s'; then
        echoColor red "Port 80 is in use! Please free port 80 first."
        echoColor yellow "Temporarily stop the service using port 80 and re-run."
        return 1
    fi

    "$ACME_HOME/acme.sh" --issue -d "$domain" --standalone --keylength ec-256 --force
    if [[ $? -ne 0 ]]; then
        echoColor red "Failed to issue certificate!"
        echoColor yellow "Make sure DNS A/AAAA records point here and :80 is reachable."
        return 1
    fi

    "$ACME_HOME/acme.sh" --install-cert -d "$domain" --ecc \
        --fullchain-file "$CERT_DIR/fullchain.cer" \
        --key-file "$CERT_DIR/private.key" \
        --reloadcmd "docker compose -f $COMPOSE_FILE restart nginx 2>/dev/null || true"

    if [[ -f "$CERT_DIR/fullchain.cer" && -f "$CERT_DIR/private.key" ]]; then
        chmod 644 "$CERT_DIR/fullchain.cer"
        chmod 600 "$CERT_DIR/private.key"
        echoColor green "Certificate installed."
        echoColor blue "  fullchain: $CERT_DIR/fullchain.cer"
        echoColor blue "  key      : $CERT_DIR/private.key"
        return 0
    else
        echoColor red "Failed to install certificate files!"
        return 1
    fi
}

function renewCertificate() {
    echoColor blue "Renewing certificates..."
    "$ACME_HOME/acme.sh" --renew-all --ecc
    if [[ $? -eq 0 ]]; then
        echoColor green "Certificates renewed."
        docker compose -f "$COMPOSE_FILE" restart nginx || true
    else
        echoColor yellow "No certificates needed renewal or renewal failed."
    fi
}

function generateRandomPath() {
    local path=$(tr -dc 'a-z0-9' </dev/urandom | fold -w 12 | head -n 1)
    echo "/$path"
}

function createDirectories() {
    mkdir -p "$BASE_DIR" "$DATA_DIR" "$CERT_DIR" "$NGINX_CONF_DIR" "$XRAY_CONF_DIR" "$CLIENT_DIR" "$DATA_DIR/nginx/html" "$DATA_DIR/shared"
    echoColor green "Directories created."
}

function createDockerCompose() {
    local port=$1

    cat <<EOF >"$COMPOSE_FILE"
version: '3.8'

services:
  xray:
    image: teddysun/xray:latest
    container_name: $XRAY_CONTAINER
    restart: always
    user: root
    volumes:
      - ./data/xray:/etc/xray:ro
      - xray_socket:/dev/shm
    networks:
      - xray_network
    command: ["xray", "run", "-c", "/etc/xray/config.json"]
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

  nginx:
    image: nginx:1.27-alpine
    container_name: $NGINX_CONTAINER
    restart: always
    ports:
      - "${port}:443/tcp"
      - "${port}:443/udp"
    volumes:
      - ./data/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./data/nginx/html:/var/www/html:ro
      - ./data/certs:/etc/nginx/certs:ro
      - xray_socket:/dev/shm
    depends_on:
      - xray
    networks:
      - xray_network

networks:
  xray_network:
    driver: bridge

volumes:
  xray_socket:
    driver: local
    driver_opts:
      type: tmpfs
      device: tmpfs
      o: size=10m,mode=1777
EOF

    # [FIX] Save port to file for later retrieval
    echo "$port" > "$DATA_DIR/port.txt"
    echoColor green "Docker Compose file created."
}

function createNginxConfig() {
    local domain=$1
    local path=$2
    local location_path="$path"
    local location_path_slash="$path/"

    cat <<EOF >"$DATA_DIR/nginx/html/index.html"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Welcome</title></head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, nginx is running.</p>
</body>
</html>
EOF

    cat <<'NGINX' >"$NGINX_CONF_DIR/nginx.conf"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    keepalive_timeout 5m;
    keepalive_requests 1000;
    keepalive_time 1h;

    client_body_buffer_size 512k;
    client_max_body_size 0;

    grpc_buffer_size 64k;

    server_tokens off;

    server {
        listen 0.0.0.0:443 ssl reuseport;
        listen [::]:443 ssl reuseport;
        listen 0.0.0.0:443 quic reuseport;
        listen [::]:443 quic reuseport;

        http2 on;

        server_name __DOMAIN__;

        ssl_certificate     /etc/nginx/certs/fullchain.cer;
        ssl_certificate_key /etc/nginx/certs/private.key;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:50m;
        ssl_session_tickets off;

        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 1.1.1.1 8.8.8.8 valid=300s;
        resolver_timeout 5s;

        add_header Alt-Svc 'h3=":443"; ma=86400' always;

        root /var/www/html;
        index index.html;

        client_header_timeout 5m;

        location / {
            try_files $uri $uri/ =404;
        }

        location ^~ __LOCATION_NO_SLASH__ {
            access_log off;
            client_body_timeout 5m;
            grpc_read_timeout 315s;
            grpc_send_timeout 5m;

            grpc_set_header Host $host;
            grpc_set_header X-Real-IP $remote_addr;
            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass unix:/dev/shm/xrxh.socket;
        }

        location ^~ __LOCATION_WITH_SLASH__ {
            access_log off;
            client_body_timeout 5m;
            grpc_read_timeout 315s;
            grpc_send_timeout 5m;

            grpc_set_header Host $host;
            grpc_set_header X-Real-IP $remote_addr;
            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass unix:/dev/shm/xrxh.socket;
        }
    }
}
NGINX

    sed -i "s|__DOMAIN__|$domain|g" "$NGINX_CONF_DIR/nginx.conf"
    sed -i "s|__LOCATION_NO_SLASH__|$location_path|g" "$NGINX_CONF_DIR/nginx.conf"
    sed -i "s|__LOCATION_WITH_SLASH__|$location_path_slash|g" "$NGINX_CONF_DIR/nginx.conf"

    echoColor green "Nginx configuration created."
}

# [FIX] Changed from xhttp to gRPC to match Nginx grpc_pass
function createXrayConfig() {
    local uuid=$1
    local path=$2
    # For gRPC, the path is the "serviceName"
    local xray_path="$path"

    cat <<EOF >"$XRAY_CONF_DIR/config.json"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "/dev/shm/xrxh.socket,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$uuid" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "$xray_path"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http","tls","quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": {} },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    echoColor green "Xray configuration created (gRPC mode)."
}

# [FIX] Changed from xhttp to gRPC for client config
function generateClientConfig() {
    local domain=$1
    local ip=$2
    local port=$3
    local uuid=$4
    local path=$5
    local client_path="$path"

    # Standard VLESS-gRPC link format with HTTP/3 support
    VLESS_LINK="vless://${uuid}@${domain}:${port}?encryption=none&security=tls&sni=${domain}&alpn=h3%2Ch2&fp=chrome&type=grpc&serviceName=${client_path}&mode=multi#gRPC-QUIC-${domain}"

    cat <<EOF >"$CLIENT_DIR/client_config.json"
{
  "log": { "loglevel": "warning" },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:cn","geoip:private"],
        "outboundTag": "direct"
      }
    ]
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": { "udp": true },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$domain",
            "port": $port,
            "users": [{ "id": "$uuid", "encryption": "none" }]
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "$client_path",
          "multiMode": true
        },
        "security": "tls",
        "tlsSettings": {
          "serverName": "$domain",
          "allowInsecure": false,
          "fingerprint": "chrome",
          "alpn": ["h3", "h2"]
        }
      },
      "tag": "proxy"
    },
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

    cat <<EOF >"$CLIENT_DIR/connection_info.txt"
===== Xray QUIC/gRPC (VLESS-gRPC-Nginx Docker) Connection Information =====
Domain: $domain
Server IP: $ip
Port: $port
UUID: $uuid
ServiceName: $client_path
Network: grpc
Security: tls
ALPN: h3, h2
SNI: $domain
Fingerprint: chrome

Certificate: $CERT_DIR/fullchain.cer
Private Key: $CERT_DIR/private.key

VLESS Link:
$VLESS_LINK
EOF

    echo "$domain" >"$DATA_DIR/domain.txt"
    echo "$client_path" >"$DATA_DIR/path.txt"

    echo ""
    echoColor green "===== Configuration Saved ====="
    echoColor blue "All configs saved to: $DATA_DIR"
    echo ""
    echoColor yellow "===== VLESS Connection Link (gRPC over QUIC) ====="
    echo "$VLESS_LINK"
    echo ""
    echoColor yellow "===== Connection Information ====="
    cat "$CLIENT_DIR/connection_info.txt"
    echo ""
    echoColor green "===== Files Created ====="
    echoColor blue "- Docker Compose: $COMPOSE_FILE"
    echoColor blue "- Xray config: $XRAY_CONF_DIR/config.json"
    echoColor blue "- Nginx config: $NGINX_CONF_DIR/nginx.conf"
    echoColor blue "- Client JSON: $CLIENT_DIR/client_config.json"
    echoColor blue "- Connection info: $CLIENT_DIR/connection_info.txt"
    echoColor blue "- Certificate: $CERT_DIR/fullchain.cer"
    echoColor blue "- Private Key: $CERT_DIR/private.key"
}

function installXrayXHTTP3() {
    echoColor yellow "===== Installing Xray gRPC/QUIC (Docker) ====="

    checkDocker || { echoColor red "Docker check failed."; return 1; }

    apt update -y
    apt install -y wget curl unzip dnsutils net-tools socat cron

    installAcme || { echoColor red "acme.sh install failed."; return 1; }

    echo ""
    echoColor yellow "===== Domain Configuration ====="
    echoColor blue "Make sure your domain's A/AAAA record points to this server."
    echo ""
    read -p "$(echoColor yellow 'Enter your domain name: ')" DOMAIN
    [[ -z "$DOMAIN" ]] && { echoColor red "Domain is required."; return 1; }

    if ! echo "$DOMAIN" | grep -qE "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"; then
        echoColor red "Invalid domain format."
        return 1
    fi

    createDirectories

    # [FIX] Check certificate BEFORE asking to re-issue
    local NEED_ISSUE=true
    if [[ -f "$CERT_DIR/fullchain.cer" && -f "$CERT_DIR/private.key" ]]; then
        echo ""
        echoColor yellow "===== Existing Certificate Found ====="
        echoColor blue "Checking certificate at: $CERT_DIR/"
        ls -la "$CERT_DIR/" 2>/dev/null
        echo ""
        
        local expiry
        expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
        local cert_domain
        cert_domain=$(openssl x509 -noout -subject -in "$CERT_DIR/fullchain.cer" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
        
        if [[ -n "$expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            local days_left=$(((expiry_epoch - now_epoch) / 86400))
            
            echoColor blue "Certificate Domain: $cert_domain"
            echoColor blue "Expires: $expiry ($days_left days left)"
            
            if [[ "$cert_domain" == "$DOMAIN" ]] && [[ $days_left -gt 7 ]]; then
                echoColor green "✓ Certificate is valid for this domain"
                echo ""
                echoColor yellow "Re-issue certificate? (default: No, timeout 6s)"
                read -t 6 -p "Re-issue? [y/N]: " re_issue_choice || re_issue_choice="n"
                if [[ "${re_issue_choice,,}" == "y" ]]; then
                    NEED_ISSUE=true
                else
                    NEED_ISSUE=false
                    echoColor green "✓ Reusing existing certificate."
                fi
            elif [[ $days_left -le 7 ]]; then
                echoColor red "⚠ Certificate expires soon ($days_left days), will re-issue."
                NEED_ISSUE=true
            elif [[ "$cert_domain" != "$DOMAIN" ]]; then
                echoColor yellow "⚠ Certificate domain ($cert_domain) doesn't match requested domain ($DOMAIN)"
                echoColor yellow "Will issue new certificate for $DOMAIN"
                NEED_ISSUE=true
            fi
        else
            echoColor red "Cannot read certificate expiry, will re-issue."
            NEED_ISSUE=true
        fi
    fi

    if [[ "$NEED_ISSUE" == "true" ]]; then
        issueCertificate "$DOMAIN" || { echoColor red "Cert issuance failed."; return 1; }
    fi

    # [FIX] 6 second timeout for port input
    echo ""
    echoColor yellow "Enter port (default: 443, timeout 6s):"
    read -t 6 -p "Port: " Port || Port=""
    Port=${Port:-443}
    
    # Validate port number
    if ! [[ "$Port" =~ ^[0-9]+$ ]] || [[ "$Port" -lt 1 ]] || [[ "$Port" -gt 65535 ]]; then
        echoColor red "Invalid port number, using default 443"
        Port=443
    fi
    echoColor blue "Using port: $Port"

    echo ""
    echoColor yellow "Path options:"
    echoColor blue "  1) STATIC /cloud (default)"
    echoColor blue "  2) RANDOM"
    echoColor blue "  3) CUSTOM"
    read -t 6 -p "$(echoColor yellow 'Select (default 1, timeout 6s): ')" path_option || path_option=""
    if [[ -z "${path_option:-}" || "$path_option" == "1" ]]; then
        PATH_VALUE="/cloud"
    elif [[ "$path_option" == "2" ]]; then
        PATH_VALUE=$(generateRandomPath)
    else
        read -p "Enter custom path (e.g., /mypath): " PATH_VALUE
        [[ "$PATH_VALUE" != /* ]] && PATH_VALUE="/$PATH_VALUE"
        PATH_VALUE="${PATH_VALUE%/}"
    fi
    echoColor green "Using path: $PATH_VALUE"

    echo ""
    echoColor yellow "UUID options:"
    echoColor blue "  1) STATIC (default)"
    echoColor blue "  2) RANDOM new"
    read -t 6 -p "$(echoColor yellow 'Select (default 1, timeout 6s): ')" uuid_option || uuid_option=""
    if [[ -z "${uuid_option:-}" || "$uuid_option" == "1" ]]; then
        UUID="12345678-1234-1234-1234-123456789012"
    else
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    echoColor green "UUID: $UUID"

    echoColor blue "Getting public IP..."
    PUBLIC_IP=$(getPublicIP)
    if [[ -z "$PUBLIC_IP" ]]; then
        echoColor red "Unable to auto-detect public IP."
        read -p "Enter server IP: " PUBLIC_IP
    fi

    echo ""
    echoColor yellow "===== Final Configuration ====="
    echoColor green "Domain : $DOMAIN"
    echoColor green "Server : $PUBLIC_IP:$Port"
    echoColor green "UUID   : $UUID"
    echoColor green "Path   : $PATH_VALUE"
    echoColor green "Proto  : VLESS-gRPC (HTTP/3 QUIC)"

    createDockerCompose "$Port"
    createNginxConfig "$DOMAIN" "$PATH_VALUE"
    createXrayConfig "$UUID" "$PATH_VALUE"

    echoColor blue "Pulling images..."
    cd "$BASE_DIR"
    docker compose pull

    echoColor blue "Starting containers..."
    docker compose up -d
    sleep 3

    if docker compose ps --status running | grep -q "$XRAY_CONTAINER"; then
        echoColor green "Xray gRPC/QUIC started."
        generateClientConfig "$DOMAIN" "$PUBLIC_IP" "$Port" "$UUID" "$PATH_VALUE"
    else
        echoColor red "Failed to start containers."
        echoColor yellow "Check logs: docker compose -f $COMPOSE_FILE logs"
        docker compose logs
    fi
}

function showStatus() {
    echoColor yellow "===== Xray gRPC/QUIC (Docker) Status ====="
    if checkInstallation; then
        echoColor green "✓ Installed"
        echoColor blue "Base: $BASE_DIR"
        echoColor blue "Data: $DATA_DIR"

        echo ""
        echoColor yellow "===== Containers ====="
        cd "$BASE_DIR"
        docker compose ps

        echo ""
        echoColor yellow "===== Certificate ====="
        if [[ -f "$CERT_DIR/fullchain.cer" ]]; then
            echoColor green "✓ Certificate exists"
            ls -la "$CERT_DIR/"
            local expiry
            expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
            if [[ -n "$expiry" ]]; then
                echoColor blue "Expires: $expiry"
                local expiry_epoch
                expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
                local now_epoch
                now_epoch=$(date +%s)
                local days_left=$(((expiry_epoch - now_epoch) / 86400))
                if [[ $days_left -lt 30 ]]; then
                    echoColor red "⚠ $days_left days left."
                else
                    echoColor green "✓ $days_left days left"
                fi
            fi
        else
            echoColor red "✗ Certificate not found"
        fi

        echo ""
        echoColor yellow "===== Xray Configuration ====="
        [[ -f "$XRAY_CONF_DIR/config.json" ]] && cat "$XRAY_CONF_DIR/config.json"

        echo ""
        if [[ -f "$CLIENT_DIR/connection_info.txt" ]]; then
            echoColor yellow "===== Connection Info ====="
            cat "$CLIENT_DIR/connection_info.txt"
        fi
    else
        echoColor red "✗ Not Installed"
    fi
}

function startService() {
    [[ -f "$COMPOSE_FILE" ]] || { echoColor red "Compose file not found."; return 1; }
    cd "$BASE_DIR"
    docker compose up -d
    sleep 2
    if docker compose ps --status running | grep -q "$XRAY_CONTAINER"; then
        echoColor green "✓ Started"
    else
        echoColor red "✗ Failed to start"
        docker compose logs
    fi
}

function stopService() {
    [[ -f "$COMPOSE_FILE" ]] || { echoColor red "Compose file not found."; return 1; }
    cd "$BASE_DIR"
    docker compose down
    echoColor green "Stopped"
}

function restartService() {
    [[ -f "$COMPOSE_FILE" ]] || { echoColor red "Compose file not found."; return 1; }
    cd "$BASE_DIR"
    docker compose restart
    sleep 2
    if docker compose ps --status running | grep -q "$XRAY_CONTAINER"; then
        echoColor green "✓ Restarted"
    else
        echoColor red "✗ Failed to restart"
        docker compose logs
    fi
}

function updateXray() {
    echoColor yellow "===== Updating images ====="
    [[ -f "$COMPOSE_FILE" ]] || { echoColor red "Compose file not found."; return 1; }
    cd "$BASE_DIR"
    docker compose ps
    docker compose pull
    docker compose up -d --force-recreate
    sleep 2
    if docker compose ps --status running | grep -q "$XRAY_CONTAINER"; then
        echoColor green "✓ Updated"
    else
        echoColor red "✗ Update failed"
        docker compose logs
    fi
}

function regenerateClientConfig() {
    echoColor yellow "===== Regenerating Client Config ====="
    [[ -f "$XRAY_CONF_DIR/config.json" ]] || { echoColor red "Xray config not found."; return 1; }

    local uuid
    uuid=$(grep -oP '"id":\s*"\K[^"]+' "$XRAY_CONF_DIR/config.json" | head -1)
    local path
    # Try to get serviceName for gRPC config, fallback to path for legacy xhttp
    path=$(grep -oP '"serviceName":\s*"\K[^"]+' "$XRAY_CONF_DIR/config.json" | head -1)
    if [[ -z "$path" ]]; then
        path=$(grep -oP '"path":\s*"\K[^"]+' "$XRAY_CONF_DIR/config.json" | head -1)
    fi

    local domain=""
    [[ -f "$DATA_DIR/domain.txt" ]] && domain=$(cat "$DATA_DIR/domain.txt")
    [[ -z "$domain" ]] && read -p "Enter domain: " domain

    # [FIX] Better port extraction - read from saved file or parse compose correctly
    local port=""
    if [[ -f "$DATA_DIR/port.txt" ]]; then
        port=$(cat "$DATA_DIR/port.txt")
    fi
    
    # Fallback: try to extract from docker-compose.yml
    if [[ -z "$port" ]] && [[ -f "$COMPOSE_FILE" ]]; then
        # Look for pattern like "443:443" or "8443:443"
        port=$(grep -oP '^\s*-\s*"\K\d+(?=:443)' "$COMPOSE_FILE" | head -1)
        if [[ -z "$port" ]]; then
            # Try without quotes
            port=$(grep -oP '^\s*-\s*\K\d+(?=:443)' "$COMPOSE_FILE" | head -1)
        fi
    fi
    
    [[ -z "$port" ]] && port=443

    echoColor blue "Domain: $domain"
    echoColor blue "Port  : $port"
    echoColor blue "UUID  : $uuid"
    echoColor blue "Path  : $path"

    local public_ip
    public_ip=$(getPublicIP)
    [[ -z "$public_ip" ]] && read -p "Enter server IP: " public_ip

    generateClientConfig "$domain" "$public_ip" "$port" "$uuid" "$path"
}

function reissueCertificate() {
    echoColor yellow "===== Re-issue TLS Certificate ====="
    local domain=""
    if [[ -f "$DATA_DIR/domain.txt" ]]; then
        domain=$(cat "$DATA_DIR/domain.txt")
        echoColor blue "Current domain: $domain"
        read -t 6 -p "Use this domain? (yes/no, default yes, timeout 6s): " use_current || use_current="yes"
        if [[ "$use_current" == "no" ]]; then
            read -p "Enter new domain: " domain
        fi
    else
        read -p "Enter domain name: " domain
    fi
    [[ -z "$domain" ]] && { echoColor red "Domain required."; return 1; }

    issueCertificate "$domain" || { echoColor red "Cert issue failed."; return 1; }

    echo "$domain" >"$DATA_DIR/domain.txt"

    if [[ -f "$COMPOSE_FILE" ]]; then
        cd "$BASE_DIR"
        docker compose restart || true
        if docker compose ps --status running | grep -q "$NGINX_CONTAINER"; then
            echoColor green "✓ Certificate re-issued & containers restarted."
            regenerateClientConfig
        else
            echoColor red "✗ Failed to restart containers"
        fi
    fi
}

function showCertificateInfo() {
    echoColor yellow "===== Certificate Information ====="
    [[ -f "$CERT_DIR/fullchain.cer" ]] || { echoColor red "Certificate not found."; return 1; }

    echoColor blue "Certificate: $CERT_DIR/fullchain.cer"
    echoColor blue "Private key: $CERT_DIR/private.key"
    echo ""
    echoColor blue "Files in cert directory:"
    ls -la "$CERT_DIR/"

    echo ""
    echoColor yellow "Details:"
    openssl x509 -noout -text -in "$CERT_DIR/fullchain.cer" | grep -A2 "Subject:" | head -3
    openssl x509 -noout -text -in "$CERT_DIR/fullchain.cer" | grep -A2 "Validity"

    echo ""
    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
    echoColor green "Expiry: $expiry"
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(((expiry_epoch - now_epoch) / 86400))
    if [[ $days_left -lt 30 ]]; then
        echoColor red "⚠ $days_left days remaining! Consider renewing."
    else
        echoColor green "✓ $days_left days remaining"
    fi

    echo ""
    echoColor yellow "acme.sh list:"
    if [[ -f "$ACME_HOME/acme.sh" ]]; then
        "$ACME_HOME/acme.sh" --list
    else
        echoColor red "acme.sh not installed"
    fi
}

function showLogs() {
    echoColor yellow "===== Container Logs ====="
    [[ -f "$COMPOSE_FILE" ]] || { echoColor red "Compose file not found."; return 1; }
    cd "$BASE_DIR"
    echo ""
    echoColor yellow "Select logs:"
    echoColor blue "  1) All"
    echoColor blue "  2) Xray"
    echoColor blue "  3) Nginx"
    read -t 6 -p "$(echoColor yellow 'Select (default 1, timeout 6s): ')" log_option || log_option="1"
    case $log_option in
      2) docker compose logs --tail=200 xray ;;
      3) docker compose logs --tail=200 nginx ;;
      *) docker compose logs --tail=200 ;;
    esac
}

function uninstallXray() {
    echoColor red "===== Uninstall Xray gRPC/QUIC (Docker) ====="
    read -p "Are you sure? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] || { echoColor blue "Canceled."; return; }

    if [[ -f "$COMPOSE_FILE" ]]; then
        cd "$BASE_DIR"
        docker compose down -v
        docker compose rm -f
    fi

    echoColor yellow "Remove all data including certificates? (yes/no): "
    read -p "" remove_data
    if [[ "$remove_data" == "yes" ]]; then
        rm -rf "$BASE_DIR"
        echoColor green "All data removed."
    else
        echoColor green "Data kept in: $DATA_DIR"
        rm -f "$COMPOSE_FILE"
    fi
}

function showMenu() {
    clear
    echoColor green "=============================================="
    echoColor green "   Xray gRPC/QUIC Manager v1.2 (Docker)"
    echoColor green "   (VLESS-gRPC-Nginx with HTTP/3 QUIC)"
    echoColor green "=============================================="
    echo ""
    if checkInstallation; then
        if checkDockerRunning; then
            echoColor green "Status: ✓ Installed & Running"
        else
            echoColor yellow "Status: Installed but Stopped"
        fi
        if [[ -f "$CERT_DIR/fullchain.cer" ]]; then
            local expiry
            expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.cer" 2>/dev/null | cut -d= -f2)
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            local days_left=$(((expiry_epoch - now_epoch) / 86400))
            if [[ $days_left -lt 30 ]]; then
                echoColor red "Certificate: ⚠ $days_left days left"
            else
                echoColor green "Certificate: ✓ $days_left days"
            fi
        fi
    else
        echoColor red "Status: Not Installed"
    fi
    echo ""
    echoColor blue "  1. Install Xray gRPC/QUIC (Docker)"
    echoColor blue "  2. Show Status & Config"
    echoColor blue "  3. Start Containers"
    echoColor blue "  4. Stop Containers"
    echoColor blue "  5. Restart Containers"
    echoColor blue "  6. Update Docker Images"
    echoColor blue "  7. Show Connection Info"
    echoColor blue "  8. Show Logs"
    echoColor blue "  9. Uninstall"
    echoColor blue " 10. Regenerate Client Config"
    echoColor blue " 11. Re-issue Certificate"
    echoColor blue " 12. Renew Certificates"
    echoColor blue " 13. Show Certificate Info"
    echoColor blue "  0. Exit"
    echo ""
}

# Main loop
while true; do
    showMenu
    read -t 6 -p "$(echoColor yellow 'Select option (default 1, timeout 6s): ')" choice || choice=""
    choice=${choice:-1}
    case $choice in
      1) if checkInstallation; then
             echoColor yellow "Already installed."
             read -t 6 -p "Reinstall? (yes/no, default yes, timeout 6s): " confirm || confirm="yes"
             confirm=${confirm:-yes}
             [[ "$confirm" == "yes" ]] && installXrayXHTTP3
         else
             installXrayXHTTP3
         fi
         read -p "Press Enter to continue..." ;;
      2) showStatus; read -p "Press Enter to continue..." ;;
      3) startService; read -p "Press Enter to continue..." ;;
      4) stopService; read -p "Press Enter to continue..." ;;
      5) restartService; read -p "Press Enter to continue..." ;;
      6) updateXray; read -p "Press Enter to continue..." ;;
      7) if [[ -f "$CLIENT_DIR/connection_info.txt" ]]; then
             cat "$CLIENT_DIR/connection_info.txt"
         else
             echoColor red "No connection info found. Install first."
         fi
         read -p "Press Enter to continue..." ;;
      8) showLogs; read -p "Press Enter to continue..." ;;
      9) uninstallXray; read -p "Press Enter to continue..." ;;
      10) regenerateClientConfig; read -p "Press Enter to continue..." ;;
      11) reissueCertificate; read -p "Press Enter to continue..." ;;
      12) renewCertificate; read -p "Press Enter to continue..." ;;
      13) showCertificateInfo; read -p "Press Enter to continue..." ;;
      0) echoColor green "Goodbye!"; exit 0 ;;
      *) echoColor red "Invalid option!"; sleep 1 ;;
    esac
done

