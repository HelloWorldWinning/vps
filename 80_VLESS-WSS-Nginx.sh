80_VLESS-WSS-Nginx_Xray() {

mkdir -p /etc/xrayZ/

read -p "input nginx_ws_path_to_vless default:/xary : " nginx_ws_path_to_vless
    if   [[ -z "$nginx_ws_path_to_vless" ]]; then
            nginx_ws_path_to_vless="/xray"
    fi


while true
        do
            read -p "input Domain ：" Domain
            if [[ -z "${Domain}" ]]; then
                echo "Domain 请重新输入！"
            else
                break
            fi
        done


cat <<EOF > /etc/nginx/conf.d/80_VLESS-WSS-Nginx.conf
server {
	listen 80;
        listen [::]:80;
        charset utf-8;
        root /usr/share/nginx/html;
	index index.html;
	
        server_name  ${Domain};


location /f/ {

    alias  /root/d.share/;
    autoindex on;
autoindex_exact_size off;
autoindex_localtime on; 
    
#fancyindex on;
#fancyindex_localtime on;
#fancyindex_exact_size off;
#charset utf-8,gbk;
#fancyindex_time_format "%Y-%m-%d %H:%M:%S";
#  fancyindex_time_format "%H:%M:%S &nbsp&nbsp&nbsp %Y-%m-%d";
#fancyindex_name_length  1024;


# find . -name "*.txt"|xargs -I {} iconv -f utf8 -tgb18030 {} -o {}
# find . -name "*.txt"|xargs -I {} iconv -f gb18030  -t utf8  {} -o {}
# apt-get install apache2-utils
#  htpasswd -c /root/passwd.txt 1
#   chmod o+r /root/passwd.txt
#
#auth_basic_user_file    /root/passwd.txt;
#auth_basic            "Restricted Area";

          }


    location / {
        proxy_ssl_server_name on;
        proxy_pass https://www.google.com;
        proxy_set_header Accept-Encoding '';
        sub_filter "www.google.com" "$Domain";
        sub_filter_once off;
       }
    
        location = /robots.txt {}



	location $nginx_ws_path_to_vless {
	if (\$http_upgrade != "websocket") {
		return 404;
	}
        proxy_pass http://unix:/dev/shm/Xray-VLESS-WSS-Nginx.socket;
	proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 52w;
    }
}
EOF


#cat <<EOF > /usr/local/etc/xray/config.json
cat <<EOF > /etc/xrayZ/config.json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "listen": "/dev/shm/Xray-VLESS-WSS-Nginx.socket,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
"id": "12345678-1234-1234-1234-123456789012"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$nginx_ws_path_to_vless"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

}

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

function echoColor() {
	case $1 in
		# 红色
	"red")
		echo -e "\033[31m${printN}$2 \033[0m"
		;;
		# 天蓝色
	"skyBlue")
		echo -e "\033[1;36m${printN}$2 \033[0m"
		;;
		# 绿色
	"green")
		echo -e "\033[32m${printN}$2 \033[0m"
		;;
		# 白色
	"white")
		echo -e "\033[37m${printN}$2 \033[0m"
		;;
	"magenta")
		echo -e "\033[31m${printN}$2 \033[0m"
		;;
		# 黄色
	"yellow")
		echo -e "\033[33m${printN}$2 \033[0m"
		;;
        # 紫色
    "purple")
        echo -e "\033[1;;35m${printN}$2 \033[0m"
        ;;
        #
    "yellowBlack")
        # 黑底黄字
        echo -e "\033[1;33;40m${printN}$2 \033[0m"
        ;;
	"greenWhite")
		# 绿底白字
		echo -e "\033[42;37m${printN}$2 \033[0m"
		;;
	esac
}



function DownloadxrayZCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest xrayZ version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`

#https://github.com/XTLS/xrayZ-core/releases/download/v1.6.1/xrayZ-linux-64.zip

temp_f=$(mktemp)
temp_d=$(mktemp -d)


    if [ $get_arch = "x86_64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -rfv $temp_d/xray /usr/bin/xrayZ
        mv -rfv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -rfv $temp_d/xray /usr/bin/xrayZ
        mv -rfv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayZ" ]; then
		chmod 755 /usr/bin/xrayZ
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayZ.service
[Unit]
Description=xrayZ Service
Documentation=https://github.com/XTLS/xrayZ-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayZ -c /etc/xrayZ/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF





apt update -y
apt upgrade -y
apt install  -y nginx
sed -i 's/include \/etc\/nginx\/sites-enabled.*/#include \/etc\/nginx\/sites-enabled\/\*;/g'  /etc/nginx/nginx.conf

systemctl stop nginx
systemctl enable nginx


}






start(){

systemctl restart  nginx
netstat  -lptnu |grep 80

           echo "/etc/xrayZ/config.json" 
           cat "/etc/xrayZ/config.json" 
    systemctl daemon-reload
    systemctl enable xrayZ
    systemctl start  xrayZ
            systemctl restart xrayZ
            systemctl status xrayZ


}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayZ${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            80_VLESS-WSS-Nginx_Xray
            DownloadxrayZCore
            start
            ;;
        2)
           echo "/etc/xrayZ/config.json" 
           cat "/etc/xrayZ/config.json" 
           systemctl status xrayZ
            ;;
	3)
systemctl restart xrayZ
systemctl status xrayZ
;;

        00)
       exit
            ;;

esac
