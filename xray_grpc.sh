
ports_to_one(){
apt-get install iptables-persistent -y

net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)

iptables -t nat -A PREROUTING -i ${net_card} -p tcp --dport 55000:60000 -j DNAT --to-destination :${Port}

ip6tables -t nat -A PREROUTING -i ${net_card} -p tcp --dport 55000:60000 -j DNAT --to-destination :${Port}


iptables-save -f /etc/iptables/rules.v4
ip6tables-save -f /etc/iptables/rules.v6


crontab -l > conf && echo  -e "@reboot sleep 13; /usr/sbin/iptables-restore < /etc/iptables/rules.v4" >> conf && crontab conf && rm -f conf

crontab -l > conf && echo  -e "@reboot sleep 14; /usr/sbin/ip6tables-restore < /etc/iptables/rules.v6" >> conf && crontab conf && rm -f conf

}





Check_Domain_Resolve () {
IPV4=$(dig  +time=1 +tries=2   @1.1.1.1 +short  txt ch  whoami.cloudflare  |tr -d \")
IPV6=$(dig  +time=1 +tries=2  +short @2606:4700:4700::1111 -6 ch txt whoami.cloudflare|tr -d \")
resolve4="$(dig  +time=1 +tries=2  A  +short ${Domain} @1.1.1.1)"
resolve6="$(dig  +time=1 +tries=2  AAAA +short ${Domain} @1.1.1.1)"
res4=`echo -n ${resolve4} | grep $IPV4`
res6=`echo -n ${resolve6} | grep $IPV6`
res=`echo $res4$res6`
echo "======"
echo "$res"
IP=`echo $res4$res6`
echo "${Domain}  points to: $res"
            if [[ -z "${res}" ]]; then
                echo " ${Domain} 解析结果：${res}"
                echo -e " ${RED}伪装域名未解析到当前服务器IP $IPV4$IPV6 !${PLAIN}"
                exit 1
               else
                    echo "$Domain successfully resolved to $res "
            fi
}



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
#echo "输入的域名为：$Domain"
Check_Domain_Resolve 

#cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
cer_path=/root/.acme.sh/${Domain}_ecc/fullchain.cer
key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key

if [[ -f $cer_path ]]  && [[ -f $key_path ]]  ; then
echo $cer_path
echo $key_path

else

Acme_Get

#cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
#key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key
      if [[ -f $cer_path ]]  && [[ -f $key_path ]]  ; then
    	echo $cer_path
    	echo $key_path
      else

	echo  "/root/.acme.sh/${Domain}_ecc/ 不存在cer key"	
	exit 1

      fi
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




Xray_Grpc() {

mkdir -p /etc/xrayG/

Get_Key_Path


read -p "Port  default: 11180: "  Port
    if   [[ -z "$Port" ]]; then
            Port=11180

    fi


read -p "input grpc serviceName default: love: " ServiceName
    if   [[ -z "$ServiceName" ]]; then
            ServiceName="love"
    fi

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


cat <<EOF > /etc/xrayG/config.json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
"port": $Port,
      "listen": "0.0.0.0",
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
	"security": "tls",
            "tlsSettings": {
                "serverName": "$Domain",
                "alpn": [ 
                    "h2"
                ],
                "certificates": [{
                    "certificateFile": "$cer_path",
                    "keyFile":  "$key_path"
                }]
            },

        "grpcSettings": {
          "serviceName": "$ServiceName" 
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

function DownloadxrayGCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest xrayG version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`

#https://github.com/XTLS/xray-core/releases/download/v1.6.1/xray-linux-64.zip

temp_f=$(mktemp)
temp_d=$(mktemp -d)


    if [ $get_arch = "x86_64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        #echo https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip

        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayG
        mv -fv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayG
        mv -fv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayG" ]; then
		chmod 755 /usr/bin/xrayG
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayG.service
[Unit]
Description=xrayG Service
Documentation=https://github.com/XTLS/xrayG-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayG -c /etc/xrayG/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF





#apt update -y
#apt upgrade -y
#apt install  -y nginx
#sed -i 's/include \/etc\/nginx\/sites-enabled.*/#include \/etc\/nginx\/sites-enabled\/\*;/g'  /etc/nginx/nginx.conf
#
#systemctl stop nginx
#systemctl enable nginx

}






start(){

netstat  -lptnu |grep $Port

           echo "/etc/xrayG/config.json" 
           cat "/etc/xrayG/config.json" 
    systemctl daemon-reload
    systemctl enable xrayG
    systemctl start  xrayG
            systemctl restart xrayG
            systemctl status xrayG


}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayG${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
		echo $Port
            Xray_Grpc
            DownloadxrayGCore
        
    ports_to_one
            start
            ;;
        2)
           echo "/etc/xrayG/config.json" 
           cat "/etc/xrayG/config.json" 
           systemctl status xrayG
            ;;
	3)
systemctl restart xrayG
systemctl status xrayG
;;

        00)
       exit
            ;;

esac
