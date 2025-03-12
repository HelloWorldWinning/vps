#!/bin/bash

# Download nginx configuration files
wget -4 -O /etc/nginx/nginx.conf.original https://raw.githubusercontent.com/HelloWorldWinning/vps/main/_etc_nginx_nginx.conf
wget -4 -O /etc/nginx/mime.types https://raw.githubusercontent.com/HelloWorldWinning/vps/main/mime.types 

# Fix nginx.conf to remove the fancyindex module that's causing the container to crash
cat /etc/nginx/nginx.conf.original | grep -v "modules/ngx_http_fancyindex_module.so" > /etc/nginx/nginx.conf

# Install required packages
docker pull nginx
apt install dnsutils -y
apt install net-tools -y
apt-get update -y

# Create necessary directories
mkdir -p /root/d.share/
mkdir -p /home/rdp/Downloads/
mkdir -p /data/ccaaDown/
mkdir -p /etc/nginx/
mkdir -p /etc/nginx/conf.d/

# Function to unlink socket files
Un_Links() {
    if ls /etc/nginx/conf.d/*.conf 1> /dev/null 2>&1; then
        grep ".sock\|.socket" /etc/nginx/conf.d/*.conf 2>/dev/null | xargs -I {} echo {} | grep -v "#" | cut -d":" -f3 | tr -d ";" | cut -d" " -f1 | xargs -I {} unlink {} 2>/dev/null || true
    fi
}

# Restart nginx and handle socket links
Restart_Ng_under_links() {
    Un_Links
}

# Check domain resolution (optional)
Check_Domain_Resolve() {
    if [[ -z "$Domain" ]]; then
        echo "Domain is not provided, skipping domain resolution check."
        return 0
    fi
    
    IPV4=$(dig +time=1 +tries=2 @1.1.1.1 +short txt ch whoami.cloudflare | tr -d \")
    IPV6=$(dig +time=1 +tries=2 +short @2606:4700:4700::1111 -6 ch txt whoami.cloudflare | tr -d \")
    resolve4="$(dig +time=1 +tries=2 A +short ${Domain} @1.1.1.1)"
    resolve6="$(dig +time=1 +tries=2 AAAA +short ${Domain} @1.1.1.1)"
    res4=`echo -n ${resolve4} | grep $IPV4`
    res6=`echo -n ${resolve6} | grep $IPV6`
    res=`echo $res4$res6`
    echo "======"
    echo "$res"
    IP=`echo $res4$res6`
    echo "${Domain} points to: $res"
    if [[ -z "${res}" ]]; then
        echo " ${Domain} 解析结果：${res}"
        echo -e " ${RED}伪装域名未解析到当前服务器IP $IPV4; $IPV6 !${PLAIN}"
        echo "Warning: Domain verification failed. Continuing anyway..."
    else
        echo "$Domain successfully resolved to $res "
    fi
}

# Get ACME certificates (only if domain is provided)
Acme_Get() {
    if [[ -z "$Domain" ]]; then
        echo "Domain is not provided, skipping certificate acquisition."
        return 1
    fi
    
    apt install socat -y
    curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
    source ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d $Domain --keylength ec-256 --force --standalone --listen-v6
}

# Get certificate paths (domain is optional)
Get_Key_Path() {
    echo "Domain is optional. If you want to use SSL or setup a reverse proxy, enter a domain."
    echo "Otherwise, just press Enter to skip domain configuration."
    
    read -p "请输入域名 (optional): " Domain
    
    if [[ -z "$Domain" ]]; then
        echo "No domain provided. Continuing without SSL certificate."
        return 0
    fi
    
    Check_Domain_Resolve 

    cer_path=/root/.acme.sh/${Domain}_ecc/fullchain.cer
    key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key

    if [[ -f $cer_path ]] && [[ -f $key_path ]]; then
        echo $cer_path
        echo $key_path
    else
        echo "No certificate found. Attempting to obtain one..."
        Acme_Get
        if [[ -f $cer_path ]] && [[ -f $key_path ]]; then
            echo $cer_path
            echo $key_path
        else
            echo "Warning: Failed to obtain certificates. Continuing without SSL."
            return 1
        fi
    fi
}

# Color definitions
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# Function to echo with color
function echoColor() {
    case $1 in
        "red")
            echo -e "\033[31m${printN}$2 \033[0m"
            ;;
        "skyBlue")
            echo -e "\033[1;36m${printN}$2 \033[0m"
            ;;
        "green")
            echo -e "\033[32m${printN}$2 \033[0m"
            ;;
        "white")
            echo -e "\033[37m${printN}$2 \033[0m"
            ;;
        "magenta")
            echo -e "\033[31m${printN}$2 \033[0m"
            ;;
        "yellow")
            echo -e "\033[33m${printN}$2 \033[0m"
            ;;
        "purple")
            echo -e "\033[1;;35m${printN}$2 \033[0m"
            ;;
        "yellowBlack")
            echo -e "\033[1;33;40m${printN}$2 \033[0m"
            ;;
        "greenWhite")
            echo -e "\033[42;37m${printN}$2 \033[0m"
            ;;
    esac
}

# Generate nginx configuration for non-SSL
nginx_conf_func() {
    read -p "port default: 9988: " Port
    if [[ -z "$Port" ]]; then
        Port=9988
    fi

    # Only call Get_Key_Path if we need to set up a domain
    if [[ "$USE_DOMAIN" == "y" ]]; then
        Get_Key_Path
    fi

    # Create config with or without domain
    if [[ -z "$Domain" ]]; then
        # Simple config without domain that points directly to d.share folder
        cat <<EOF > /etc/nginx/conf.d/${Port}.conf.docker
server {
    listen $Port;
    listen [::]:$Port;

    charset utf-8;
    
    # Main location block for / - will render index.html if it exists
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        autoindex on;
        autoindex_exact_size off; 
        autoindex_localtime on;     
        charset utf-8,gbk;
    }

    location /rdp {
        alias /home/rdp/Downloads/; 
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }

    location /ccaa {
        alias /data/ccaaDown/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }
    
    location = /robots.txt {}
}
EOF
    else
        # Config with domain and Google proxy
        cat <<EOF > /etc/nginx/conf.d/${Port}.conf.docker
server {
    listen $Port;
    listen [::]:$Port;
    server_name $Domain;

    charset utf-8;
    
    # Main location block for / - will render index.html if it exists
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        autoindex on;
        autoindex_exact_size off; 
        autoindex_localtime on;     
        charset utf-8,gbk;
    }

    location /rdp {
        alias /home/rdp/Downloads/; 
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }

    location /ccaa {
        alias /data/ccaaDown/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }
    
    location /google {
        proxy_ssl_server_name on;
        proxy_pass https://www.google.com;
        proxy_set_header Accept-Encoding '';
        sub_filter "www.google.com" "$Domain";
        sub_filter_once off;
    }
    
    location = /robots.txt {}
}
EOF
    fi
}

# Generate nginx configuration for SSL
nginx_conf_func443() {
    read -p "port default: 443: " Port
    if [[ -z "$Port" ]]; then
        Port=443
    fi

    # SSL requires a domain
    Get_Key_Path
    
    if [[ -z "$Domain" ]]; then
        echo "Cannot set up SSL without a domain. Exiting..."
        exit 1
    fi

    cat <<EOF > /etc/nginx/conf.d/${Port}.conf.docker
server {
    listen $Port ssl;
    listen [::]:$Port ssl;
    server_name $Domain;

    charset utf-8;
    
    ssl_certificate $cer_path;
    ssl_certificate_key $key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    
    client_header_timeout 52w;
    keepalive_timeout 52w;

    # Main location block for / - will render index.html if it exists
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        autoindex on;
        autoindex_exact_size off; 
        autoindex_localtime on;     
        charset utf-8,gbk;
    }

    location /rdp {
        alias /home/rdp/Downloads/; 
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }

    location /ccaa {
        alias /data/ccaaDown/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on; 
    }
    
    location /google {
        proxy_ssl_server_name on;
        proxy_pass https://www.google.com;
        proxy_set_header Accept-Encoding '';
        sub_filter "www.google.com" "$Domain";
        sub_filter_once off;
    }
    
    location = /robots.txt {}
}
EOF
}

# Function to create docker-compose.yml
create_docker_compose() {
    read -p "Enter docker-compose.yml full path (default: /data/nginx_docker_d): " DOCKER_COMPOSE_PATH
    if [[ -z "$DOCKER_COMPOSE_PATH" ]]; then
        DOCKER_COMPOSE_PATH="/data/nginx_docker_d"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p $DOCKER_COMPOSE_PATH
    mkdir -p $DOCKER_COMPOSE_PATH/d.share
    
    # Clean up any existing containers with the same name before creating new ones
    if docker ps -a | grep -q "nginx-$Port\|$Port$"; then
        echo "Found existing containers with the same port name. Removing..."
        docker stop nginx-$Port 2>/dev/null || true
        docker stop $Port 2>/dev/null || true
        docker rm nginx-$Port 2>/dev/null || true
        docker rm $Port 2>/dev/null || true
    fi
    
    # Create sample files in d.share (including a sample index.html)
    echo "This is a test file." > $DOCKER_COMPOSE_PATH/d.share/test.txt
    echo "Another test file." > $DOCKER_COMPOSE_PATH/d.share/test2.txt
    
    # Create a sample index.html file that will be rendered
    cat <<EOF > $DOCKER_COMPOSE_PATH/d.share/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Nginx File Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
        }
        ul {
            list-style-type: none;
            padding: 0;
        }
        li {
            margin: 10px 0;
            padding: 10px;
            background-color: #f8f9fa;
            border-left: 4px solid #007bff;
            border-radius: 4px;
        }
        a {
            color: #007bff;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Your Nginx File Server</h1>
        <p>This is a working index.html file. If you see this page, your Nginx configuration is working correctly and rendering HTML files properly.</p>
        
        <h2>Available Directories:</h2>
        <ul>
            <li><a href="/">Root Directory</a> - Contains files in the root directory</li>
            <li><a href="/rdp">RDP Downloads</a> - Access files in the RDP downloads folder</li>
            <li><a href="/ccaa">CCAA Downloads</a> - Access files in the CCAA downloads folder</li>
        </ul>
        
        <h2>Sample Files:</h2>
        <ul>
            <li><a href="/test.txt">test.txt</a> - A sample text file</li>
            <li><a href="/test2.txt">test2.txt</a> - Another sample text file</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    if [[ "$Port" == "443" ]]; then
        # SSL enabled docker-compose (without version)
        cat <<EOF > $DOCKER_COMPOSE_PATH/docker-compose.yml
services:
  nginx:
    image: nginx
    container_name: nginx-$Port
    restart: always
    ports:
      - "$Port:$Port"
    volumes:
      - /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/nginx/mime.types:/etc/nginx/mime.types:ro
      - /etc/nginx/conf.d/${Port}.conf.docker:/etc/nginx/conf.d/default.conf:ro
      - $DOCKER_COMPOSE_PATH/d.share:/usr/share/nginx/html
      - /home/rdp/Downloads/:/home/rdp/Downloads/
      - /data/ccaaDown/:/data/ccaaDown/
      - $cer_path:$cer_path:ro
      - $key_path:$key_path:ro
EOF
    else
        # Non-SSL docker-compose (without version)
        cat <<EOF > $DOCKER_COMPOSE_PATH/docker-compose.yml
services:
  nginx:
    image: nginx
    container_name: nginx-$Port
    restart: always
    ports:
      - "$Port:$Port"
    volumes:
      - /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/nginx/mime.types:/etc/nginx/mime.types:ro
      - /etc/nginx/conf.d/${Port}.conf.docker:/etc/nginx/conf.d/default.conf:ro
      - $DOCKER_COMPOSE_PATH/d.share:/usr/share/nginx/html
      - /home/rdp/Downloads/:/home/rdp/Downloads/
      - /data/ccaaDown/:/data/ccaaDown/
    privileged: true
EOF
    fi
    
    echo "Docker Compose file created at $DOCKER_COMPOSE_PATH/docker-compose.yml"
    echo "Share directory created at $DOCKER_COMPOSE_PATH/d.share"
    echo "Test files created at $DOCKER_COMPOSE_PATH/d.share/"
    echo "Sample index.html created at $DOCKER_COMPOSE_PATH/d.share/index.html"
}

# Function to deploy with docker-compose
deploy_docker_compose() {
    cd $DOCKER_COMPOSE_PATH
    echo "Pulling latest nginx image..."
    docker compose pull
    echo "Stopping any existing container..."
    docker compose stop
    echo "Starting new container..."
    docker compose up -d
    
    echo "Docker Compose deployed successfully"
    docker ps -a | grep nginx
    
    # Get the public IP address of the server
    PUBLIC_IPV4=$(curl -s -4 ifconfig.co 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || curl -s -4 api.ipify.org 2>/dev/null || dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    
    if [[ -z "$PUBLIC_IPV4" ]]; then
        # Fallback method for getting IP
        PUBLIC_IPV4=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
        if [[ -z "$PUBLIC_IPV4" ]]; then
            PUBLIC_IPV4="YOUR_SERVER_IP"
        fi
    fi
    
    echo ""
    echo "====================================="
    echo "Your file server is now accessible at:"
    echo "http://$PUBLIC_IPV4:$Port/"
    echo "====================================="
}

# Main menu
echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}docker nginx port (文件服务器)${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 安装 ${BLUE}docker nginx port 有域名${PLAIN}"
echo -e "  ${GREEN}443.${PLAIN} 安装 ${BLUE}docker nginx 443 (需要域名)${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}4.${PLAIN} restart ${BLUE}Restart_Ng_under_links${PLAIN}"
echo -e "  ${GREEN}5.${PLAIN}  ${RED}check docker command${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"

read -p " 选择：" answer
case $answer in
    1)
        USE_DOMAIN="n"
        nginx_conf_func
        create_docker_compose
        deploy_docker_compose
        ;;
    2)
        USE_DOMAIN="y"
        nginx_conf_func
        create_docker_compose
        deploy_docker_compose
        ;;
    443)
        USE_DOMAIN="y"
        nginx_conf_func443
        create_docker_compose
        deploy_docker_compose
        ;;
    3)
        ls -lt /etc/nginx/conf.d
        docker ps -a
        ;;
    4)
        Restart_Ng_under_links
        ;;
    5)
        curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/new_nginx_conf.txt.sh
        ;;
    00)
        exit
        ;;
esac
