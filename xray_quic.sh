
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
                echo -e " ${RED}伪装域名未解析到当前服务器IP $IPV4; $IPV6 !${PLAIN}"
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



xray_tuic() {

mkdir -p /etc/xrayQuic/

#Get_Key_Path

read -p "port  default: 44500: " Port
    if   [[ -z "$Port" ]]; then
            Port=44500

    fi



cat <<EOF > /etc/xrayQuic/config.json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
    "listen": "0.0.0.0",
    "port": $Port,
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

		"network": "quic",
		  "quicSettings": { 
		  "security": "none",
		  "key": "",
		  "header": {
		    "type":"wechat-video" 
		      }
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



function DownloadxrayQuicCore(){
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
        mv -fv $temp_d/xray /usr/bin/xrayQuic
        mv -fv $temp_d/* /usr/bin/

         
    elif [ $get_arch = "aarch64" ];then
        wget -q -O $temp_f  --no-check-certificate https://github.com/XTLS/xray-core/releases/download/${version}/xray-linux-64.zip
        unzip $temp_f -d $temp_d/
        mv -fv $temp_d/xray /usr/bin/xrayQuic
        mv -fv $temp_d/* /usr/bin/
   
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/XTLS/xray-core/releases/"
        exit
    fi
	if [ -f "/usr/bin/xrayQuic" ]; then
		chmod 755 /usr/bin/xrayQuic
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi


	cat <<EOF > /etc/systemd/system/xrayQuic.service
[Unit]
Description=xrayQuic Service
Documentation=https://github.com/XTLS/xrayQuic-core/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xrayQuic -c /etc/xrayQuic/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF



}



start(){

           echo "/etc/xrayQuic/config.json" 
           cat "/etc/xrayQuic/config.json" 
    systemctl daemon-reload
    systemctl enable xrayQuic
    systemctl start  xrayQuic
            systemctl restart xrayQuic
            systemctl status xrayQuic

}


echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}xrayQuic${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            xray_tuic
            DownloadxrayQuicCore
            start
systemctl restart xrayQuic
systemctl status xrayQuic
           echo "/etc/xrayQuic/config.json" 
           cat "/etc/xrayQuic/config.json" 
            ;;
        2)
           echo "/etc/xrayQuic/config.json" 
           cat "/etc/xrayQuic/config.json" 
           echo "/etc/xrayQuic/config.json" 
           systemctl status xrayQuic
            ;;
	3)
systemctl restart xrayQuic
echo "/etc/xrayQuic/config.json" 
cat "/etc/xrayQuic/config.json" 
systemctl status xrayQuic
;;

        00)
       exit
            ;;

esac
