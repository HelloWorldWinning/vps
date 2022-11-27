
Acme_Get(){

apt install socat -y
curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
source ~/.bashrc
~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh   --issue -d $Domain --keylength ec-256 --force  --standalone --listen-v6

}

Get_Key_Path(){

echo "如果~/.acme.sh下没有正确域名 ，请确保80端口没有被占用，脚本自动获取域名"
  
read -p "请正确输入域名: " Domain
cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key

if [[ -f $cer_path ]]  && [[ -f $key_path ]]  ; then
echo $cer_path
echo $key_path

else

Acme_Get

cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key
echo $cer_path
echo $key_path

fi


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



Xray_Grpc_Nginx() {

mkdir -p /etc/xrayR/

Get_Key_Path

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


#while true
#        do
#            read -p "Domain ："  Domain
#            if [[ -z "${Domain}" ]]; then
#                echo "Domain 请重新输入！"
#            else
#                break
#            fi
#        done
#
#
#while true
#        do
#            read -p " 请输入cer path：" cer_path
#            if [ ! -f "${cer_path}" ]; then
#                echoColor red " certificate path wrong，请重新输入！"
#				echoColor green "请输入证书cert文件路径:"
#            else
#                break
#            fi
#        done
#
#while true
#        do
#            read -p " 请输入key path：" key_path
#            if [ !  -f "${key_path}" ]; then
#                echoColor red " key path wrong，请重新输入！"
#				echoColor green "请输入证书key文件路径:"
#            else
#                break
#            fi
#        done
#
#

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
		if (\$request_method != "POST") {
                    return 404;
                
                }		

#		client_max_body_size 0;
#		client_body_buffer_size 512k;
#		grpc_set_header X-Real-IP \$remote_addr;
#		client_body_timeout 52w;
#		grpc_read_timeout 52w;
		grpc_pass unix:/dev/shm/Nginx_to_Xray_VLESS_gRPC.socket;
   
         # https://chirpset.com/t/topic/310  断流
		keepalive_timeout 7d;
		keepalive_requests 100000;

                client_max_body_size 0;
                client_body_buffer_size 8k;
            	client_body_timeout 300s;
                grpc_read_timeout 1d;
                grpc_send_timeout 1d;

	        grpc_set_header Connection "";
                grpc_connect_timeout 10s;
                proxy_buffering off;
                #grpc_buffer_size 100m;
                grpc_socket_keepalive on;
                #grpc_pass grpc:/dev/shm/Nginx_to_Xray_VLESS_gRPC.socket;

grpc_set_header X-Real-IP \$remote_addr;
grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;


		

	}
}
EOF




serviceName=$(echo $nginx_grpc_path_to_vless|tr -d "\/" )

cat <<EOF > /etc/xrayR/config.json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "listen": "/dev/shm/Nginx_to_Xray_VLESS_gRPC.socket,0666",
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

systemctl enable nginx
#systemctl stop nginx


}



start(){
unlink /dev/shm/Nginx_to_Xray_VLESS_gRPC.socket
systemctl start  nginx
systemctl reload nginx

netstat  -lptnu |grep  $Port

           echo "/etc/xrayR/config.json" 
           cat "/etc/xrayR/config.json" 
    systemctl daemon-reload
    systemctl enable xrayR
    systemctl start  xrayR
            systemctl restart xrayR
            systemctl status xrayR

}

get_nginx_port(){
nginx_conf_file=$(grep -r Nginx_to_Xray_VLESS_gRPC.socket /etc/nginx/conf.d/* |cut -d ":" -f1)

nginx_port=$(cat /etc/nginx/conf.d/Nginx_22280_Grpc_path_to_vless.conf|grep listen |head -1 |cut -d" " -f2)
}

get_nginx_port

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
	    get_nginx_port
netstat -ltnp  |grep nginx |grep $nginx_port
            ;;
        2)
           echo "/etc/xrayR/config.json" 
           cat "/etc/xrayR/config.json" 
	   get_nginx_port
netstat -ltnp  |grep nginx  |grep  $nginx_port
           systemctl status xrayR
            ;;
	3)
unlink  /dev/shm/Nginx_to_Xray_VLESS_gRPC.socket
systemctl restart nginx

get_nginx_port

netstat -ltnp  |grep  nginx |grep  $nginx_port
systemctl restart xrayR
systemctl status xrayR
;;

        00)
       exit
            ;;

esac
