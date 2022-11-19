
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



Xray_Grpc_Nginx() {

mkdir -p /etc/xrayR/

read -p "port  default: 22280: " Port
    if   [[ -z "$Port" ]]; then
            Port=22280

    fi

read -p "input nginx_grpc_path_to_vless default:/love : " nginx_grpc_path_to_vless
    if   [[ -z "$nginx_grpc_path_to_vless" ]]; then
            nginx_grpc_path_to_vless="/love"
    fi

#read -p "input grpc serviceName default: love: " ServiceName
#    if   [[ -z "$ServiceName" ]]; then
#            ServiceName="love"
#    fi


while true
        do
            read -p "Domain ："  Domain
            if [[ -z "${Domain}" ]]; then
                echo "Domain 请重新输入！"
            else
                break
            fi
        done


while true
        do
            read -p " 请输入cer path：" cer_path
            if [ ! -f "${cer_path}" ]; then
                echoColor red " certificate path wrong，请重新输入！"
				echoColor green "请输入证书cert文件路径:"
            else
                break
            fi
        done

while true
        do
            read -p " 请输入key path：" key_path
            if [ !  -f "${key_path}" ]; then
                echoColor red " key path wrong，请重新输入！"
				echoColor green "请输入证书key文件路径:"
            else
                break
            fi
        done



cat <<EOF > /etc/nginx/conf.d/Nginx_${Port}_Grpc_path_to_vless.conf
server {
	listen $Port ssl http2 so_keepalive=on;
        listen [::]:$Port ssl http2 so_keepalive=on;
	server_name   $Domain;

	index index.html;
	root /var/www/html;

	ssl_certificate  $cer_path  ;
	ssl_certificate_key  $key_path;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
	
	client_header_timeout 52w;
        keepalive_timeout 52w;


    location / {
        proxy_ssl_server_name on;
        proxy_pass https://www.google.com;
        proxy_set_header Accept-Encoding '';
        sub_filter "www.google.com" "$Domain";
        sub_filter_once off;
       }
    
        location = /robots.txt {}


	# 在 location 后填写 /你的 ServiceName

	location $nginx_grpc_path_to_vless {
		if (\$content_type !~ "application/grpc") {
			return 404;
		}
		client_max_body_size 0;
		client_body_buffer_size 512k;
		grpc_set_header X-Real-IP \$remote_addr;
		client_body_timeout 52w;
		grpc_read_timeout 52w;
		grpc_pass unix:/dev/shm/Xray-VLESS-gRPC.socket;
	}
}
EOF




serviceName=$(echo $nginx_grpc_path_to_vless|tr -d "\/" )

cat <<EOF > /etc/xrayR/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "/dev/shm/Xray-VLESS-gRPC.socket,0666",
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
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "$serviceName"
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



function DownloadxrayRCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest xray version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`

#https://github.com/XTLS/xrayZ-core/releases/download/v1.6.1/xrayZ-linux-64.zip

temp_f=$(mktemp)
temp_d=$(mktemp -d)


    if [ $get_arch = "x86_64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayR
        mv -fv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayR
        mv -fv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayR" ]; then
		chmod 755 /usr/bin/xrayR
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayR.service
[Unit]
Description=xrayR Service
Documentation=https://github.com/XTLS/xrayR-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayR -c /etc/xrayR/config.json
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
#unlink /dev/shm/Xray-VLESS-to-Nginx.socket
unlink /dev/shm/Xray-VLESS-gRPC.socket
systemctl restart  nginx
netstat  -lptnu |grep  $Port

           echo "/etc/xrayR/config.json" 
           cat "/etc/xrayR/config.json" 
    systemctl daemon-reload
    systemctl enable xrayR
    systemctl start  xrayR
            systemctl restart xrayR
            systemctl status xrayR


}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayR${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            Xray_Grpc_Nginx
            DownloadxrayRCore
            start
            ;;
        2)
           echo "/etc/xrayR/config.json" 
           cat "/etc/xrayR/config.json" 
netstat -ltnp  |grep nginx 
           systemctl status xrayR
            ;;
	3)
unlink /dev/shm/Xray-VLESS-gRPC.socket
netstat -ltnp  |grep  nginx
systemctl restart xrayR
systemctl status xrayR
;;

        00)
       exit
            ;;

esac
