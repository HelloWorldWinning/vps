Check_Domain_Resolve () {

# Identify the primary network interface (regardless of wg status)
PRIMARY_NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}')

# Get the authentic public IP by querying Cloudflare's DNS server 1.1.1.1
IPV4=$(dig @1.1.1.1 whoami.cloudflare ch txt +short -b $(ip -4 addr show $PRIMARY_NETWORK_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}') | tr -d '"')

# Identify the primary network interface (regardless of wg status)
PRIMARY_NETWORK_INTERFACE_ipv6=$(ip -6 route | grep default | awk '{print $5}'|head -1)

# Get all available IPv6 addresses for the interface
IPV6_ADDRESSES=$(ip -6 addr show $PRIMARY_NETWORK_INTERFACE_ipv6 | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+')

# Get the authentic public IPv6 by querying Cloudflare's DNS server using available IPv6 addresses
for IPV6_ADDRESS in $IPV6_ADDRESSES; do
  IPV6=$(dig @2606:4700:4700::1111 whoami.cloudflare ch txt +short -b $IPV6_ADDRESS | tr -d '"')
  if [ ! -z "$IPV6" ]; then
    break
  fi
done


#IPV4=$(dig  +time=1 +tries=2   @1.1.1.1 +short  txt ch  whoami.cloudflare  |tr -d \")
#IPV6=$(dig  +time=1 +tries=2  +short @2606:4700:4700::1111 -6 ch txt whoami.cloudflare|tr -d \")
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




Xray_Reality() {

mkdir -p /etc/Reality/

#Get_Key_Path

read -p "Port  default: 60001: "  Port
    if   [[ -z "$Port" ]]; then
            Port=60001

    fi


#read -p "input serviceName sni : www.cloudflare.com " ServiceName
#    if   [[ -z "$ServiceName" ]]; then
#            ServiceName="www.cloudflare.com"
#    fi



cat <<EOF > /etc/Reality/config.yaml
---
log:
# loglevel: debug
  loglevel: none
inbounds:
- port: $Port
  protocol: vless
  settings:
    clients:
    - id: 12345678-1234-1234-1234-123456789012
      flow: xtls-rprx-vision
    decryption: none
  streamSettings:
    network: tcp
    security: reality
    realitySettings:
      dest: www.cloudflare.com:443
      serverNames:
      - www.cloudflare.com
      privateKey: YAjoKYIZ601zDTrYJKGoibA0bNTKCboCJNGUH7wgdn4
      shortIds:
      - ''
  sniffing:
    enabled: true
    destOverride:
    - http
    - tls
    - quic
    routeOnly: true
outbounds:
- protocol: freedom
  tag: direct
EOF





}

function DownloadxrayRealityCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/XTLS/xray-core/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest xray version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`

#https://github.com/XTLS/xray-core/releases/download/v1.6.1/xray-linux-64.zip

temp_f=$(mktemp)
temp_d=$(mktemp -d)


    if [ $get_arch = "x86_64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        #echo https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip

        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayReality
        mv -fv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/Xray-linux-arm64-v8a.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayReality
        mv -fv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayReality" ]; then
		chmod 755 /usr/bin/xrayReality
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayReality.service
[Unit]
Description=xrayReality Service
Documentation=https://github.com/XTLS/xray-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayReality -c /etc/xrayReality/config.json
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

           echo "/etc/xrayReality/config.json" 
           cat "/etc/xrayReality/config.json" 
    systemctl daemon-reload
    systemctl enable xrayReality
    systemctl start  xrayReality
            systemctl restart xrayReality
            systemctl status xrayReality


}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayReality${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            Xray_Reality
            DownloadxrayRealityCore
            start
            ;;
        2)
           echo "/etc/xrayReality/config.json" 
           cat "/etc/xrayReality/config.json" 
           systemctl status xrayReality
            ;;
	3)
systemctl restart xrayReality
systemctl status xrayReality
;;

        00)
       exit
            ;;

esac
