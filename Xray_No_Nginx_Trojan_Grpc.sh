

Acme_Get(){
apt install socat -y
curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
source ~/.bashrc
~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh   --issue -d $Domain --keylength ec-256 --force  --standalone --listen-v6
}

Get_Key_Path(){

echo "如果~/.acme.sh下没有正确的域名cer/key ，请确保80端口没有被占用，脚本自动获取域名"
  
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



Xray_Trojan_No_Nginx() {

mkdir -p /etc/xrayTnoNginx/

read -p "port  default: 44480: " Port
    if   [[ -z "$Port" ]]; then
            Port=44480

    fi

read -p "xtls/tls default: xtls  "  Xtls
     if   [[ -z "$Xtls" ]]; then
             Xtls="xtls"
	else
	    Xtls="tls"
      fi
 
if [[ "$Xtls" == "xtls" ]]; then
xtls_option='"flow": "xtls-rprx-direct",'
else
xtls_option=''
fi

Get_Key_Path

#read -p "input nginx_grpc_path_to_vless default:/love : " nginx_grpc_path_to_vless
#    if   [[ -z "$nginx_grpc_path_to_vless" ]]; then
#            nginx_grpc_path_to_vless="/love"
#    fi

#read -p "input grpc serviceName default: love: " ServiceName
#    if   [[ -z "$ServiceName" ]]; then
#            ServiceName="love"
#    fi

#
#
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

#serviceName=$(echo $nginx_grpc_path_to_vless|tr -d "\/" )





cat <<EOF > /etc/xrayTnoNginx/config.json
{
    "log": {
        "loglevel": "debug"
    },
    "inbounds": [
        {
            "port": $Port,
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
			$xtls_option	
                        "password":"1"  
                    }
                ] ,

                "fallbacks": [
                    {
                        "dest": "/dev/shm/vless_trojan_to_nginx.sock",
                        "xver": 1
                    },
                    {
                        "alpn": "h2",
                        "dest": "/dev/shm/h2vless_trojan_to_nginx.sock",
                        "xver": 1
                    }
                ]


            },
            "streamSettings": {
                "network": "tcp",
                "security": "$Xtls",
                "xtlsSettings": {
                    "alpn": [
                        "http/1.1",
                        "h2"
                    ],
                    "certificates": [
                        {
                            "certificateFile": "$cer_path", 
                            "keyFile": "$key_path", 
                            "ocspStapling": 3600  
                        }
                    ],
                    "minVersion": "1.2" 
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF


cat <<EOF > /etc/nginx/conf.d/Nginx_${Port}_unix_vless_trojan_to_nginx.sock.conf
server {

listen unix:/dev/shm/vless_trojan_to_nginx.sock  proxy_protocol;	
listen unix:/dev/shm/h2vless_trojan_to_nginx.sock http2 proxy_protocol;

    location / {
        proxy_ssl_server_name on;
        proxy_pass https://www.google.com;
        proxy_set_header Accept-Encoding '';
        sub_filter "www.google.com" "$Domain";
        sub_filter_once off;
       }
}
EOF




}



function DownloadxrayTnoNginxCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest xray version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`

#https://github.com/XTLS/xray-core/releases/download/v1.6.1/xray-linux-64.zip

temp_f=$(mktemp)
temp_d=$(mktemp -d)


    if [ $get_arch = "x86_64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayTnoNginx
        mv -fv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayTnoNginx
        mv -fv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayTnoNginx" ]; then
		chmod 755 /usr/bin/xrayTnoNginx
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayTnoNginx.service
[Unit]
Description=xray Service
Documentation=https://github.com/XTLS/xray-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayTnoNginx -c /etc/xrayTnoNginx/config.json
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
unlink /dev/shm/vless_trojan_to_nginx.sock
unlink /dev/shm/h2vless_trojan_to_nginx.sock 
#systemctl restart  nginx
systemctl  reload nginx
netstat  -lptnu 

           echo "/etc/xrayTnoNginx/config.json" 
           cat "/etc/xrayTnoNginx/config.json" 
    systemctl daemon-reload
    systemctl enable xrayTnoNginx
    systemctl start  xrayTnoNginx
            systemctl restart xrayTnoNginx
            systemctl status xrayTnoNginx


}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayTnoNginx${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            Xray_Trojan_No_Nginx
            DownloadxrayTnoNginxCore
            start
netstat -ltnp
            ;;
        2)
           echo "/etc/xrayTnoNginx/config.json" 
           cat "/etc/xrayTnoNginx/config.json" 
netstat -ltnp  
           systemctl status xrayTnoNginx
            ;;
	3)
unlink /dev/shm/vless_trojan_to_nginx.sock
unlink /dev/shm/h2vless_trojan_to_nginx.sock 
#systemctl restart nginx
systemctl  reload nginx
netstat -ltnp 
systemctl restart xrayTnoNginx
systemctl status xrayTnoNginx
;;

        00)
       exit
            ;;

esac
