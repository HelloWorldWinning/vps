
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

function downloadTuicCore(){
	version=`wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/EAimTY/tuic/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'`
	wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/EAimTY/tuic/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g'
	echo -e "The Latest tuic version:"`echoColor red "${version}"`"\nDownload..."
    get_arch=`arch`
    # https://github.com/EAimTY/tuic/releases/download/0.8.5/tuic-server-0.8.5-x86_64-linux-arm64-musl  
    # https://github.com/EAimTY/tuic/releases/download0.8.5/tuic-server0.8.5-x86_64-linux-musl
    if [ $get_arch = "x86_64" ];then

url=$(curl https://api.github.com/repos/EAimTY/tuic/releases/latest | grep x86_64 | grep inux-musl | grep -v sha256sum | awk -F\" '/browser_download_url/{print $4}')
wget  -4 -O  /usr/bin/Tuic --no-check-certificate $url

#wget  --inet4-only  -O /usr/bin/Tuic   $url

        

       #  echo "https://github.com/EAimTY/tuic/releases/download/${version}/tuic-server-"${version}"-${get_arch}-linux-musl"
         
    elif [ $get_arch = "aarch64" ];then
#        wget -q -O /usr/bin/Tuic --no-check-certificate https://github.com/EAimTY/tuic/releases/download/${version}/tuic-server-"${version}"-"${get_arch}"-linux-musl
url=$(curl https://api.github.com/repos/EAimTY/tuic/releases/latest | grep aarch64 | grep inux-musl | grep -v sha256sum | awk -F\" '/browser_download_url/{print $4}')
wget  -4 -O  /usr/bin/Tuic --no-check-certificate $url
   
	elif [ $get_arch = "i386" ];then
#       wget -q -O /usr/bin/Tuic --no-check-certificate https://github.com/EAimTY/tuic/releases/download/${version}/tuic-server-"${version}"-"${get_arch}"-macos
url=$(curl https://api.github.com/repos/EAimTY/tuic/releases/latest | grep  i386 | grep inux-musl | grep -v sha256sum | awk -F\" '/browser_download_url/{print $4}')
wget  -4 -O  /usr/bin/Tuic --no-check-certificate $url
    else
        echoColor yellowBlack "Error[OS Message]:${get_arch}\nPlease open a issue to https://github.com/EAimTY/tuic/releases/"
        exit
    fi
	if [ -f "/usr/bin/Tuic" ]; then
		chmod 755 /usr/bin/Tuic
		echoColor purple "\nDownload completed."
	else
		echoColor red "Network Error: Can't connect to Github!"
	fi
}

config(){


Get_Key_Path

read -p "监听v6端口默认44499:" ListenPort6
    if   [[ -z "$ListenPort6" ]]; then
            ListenPort6="44499"

    fi



read -p "default:bbr/bbr2:" bbrbbr2
    if   [[ -z "$bbrbbr2" ]]; then
            bbrbbr2="bbr"

    fi


#
#read -p "监听v4端口默认55554:" ListenPort4
#    if   [[ -z "$ListenPort4" ]]; then
#            ListenPort4="55554"
#
#    fi

read -p "Token默认1:" TokenPassword
    if   [[ -z "$TokenPassword" ]]; then
            TokenPassword="1"

    fi

#while true
#        do
#            read -p " 请输入cer path：" cert_path
#            if [[ -z "${cert_path}" ]]; then
#                echoColor red " certificate path wrong，请重新输入！"
#            else
#                break
#            fi
#        done
#
#while true
#        do
#            read -p " 请输入key path：" key_path
#            if [[ -z "${key_path}" ]]; then
#                echoColor red " key path wrong，请重新输入！"
#            else
#                break
#            fi
#        done
#

mkdir -p /etc/tuic/

#
#		cat <<EOF > /etc/tuic/config4.json
#{
#    "port": ${ListenPort4},
#    "token": ["1"],
#    "certificate": "${cert_path}",
#    "private_key": "${key_path}",
#
#    "ip": "0.0.0.0",
#    "congestion_controller": "bbr",
#    "max_idle_time": 15000,
#    "authentication_timeout": 1000,
#    "alpn": ["h3"],
#    "max_udp_relay_packet_size": 1500,
#    "log_level": "info"
#}
#EOF
#

#{
#    "port":${ListenPort6},
#    "token": ["1"],
#    "certificate": "${cer_path}",
#    "private_key": "${key_path}",
#
#    "ip": "::",
#    "congestion_controller": "${bbrbbr2}",
#    "max_idle_time": 15000,
#    "authentication_timeout": 1000,
#    "alpn": ["h3"],
#    "max_udp_relay_packet_size": 1500,
#    "log_level": "info"
#}


	cat <<EOF > /etc/tuic/config.json

{
    "server": "[::]:${ListenPort6}",

    "users": {
        "12345678-1234-1234-1234-123456789012": "1"
    },

    "certificate":  "${cer_path}",

    "private_key": "${key_path}", 

    "congestion_control":"${bbrbbr2}",

    "alpn": ["h3", "spdy/3.1"],

    "udp_relay_ipv6": true,

    "zero_rtt_handshake": false,

    "dual_stack": true,

    "auth_timeout": "3s",

    "task_negotiation_timeout": "3s",

    "max_idle_time": "10s",

    "max_external_packet_size": 1500,

    "send_window": 16777216,

    "receive_window": 8388608,

    "gc_interval": "3s",

    "gc_lifetime": "15s",

    "log_level": "warn"
}




EOF



#
#	cat <<EOF > /etc/systemd/system/tuic4.service
#[Unit]
#Description=Tuic Service
#Documentation=https://github.com/EAimTY/tuic/
#After=network.target nss-lookup.target
#
#[Service]
#User=root
##User=nobody
##CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
##AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#NoNewPrivileges=true
#ExecStart=/usr/bin/Tuic -c /etc/tuic/config4.json
#Restart=on-failure
#RestartPreventExitStatus=23
#
#[Install]
#WantedBy=multi-user.target
#EOF
#


	cat <<EOF > /etc/systemd/system/tuic.service
[Unit]
Description=Tuic Service
Documentation=https://github.com/EAimTY/tuic/
After=network.target nss-lookup.target

[Service]
User=root
#User=nobody
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/Tuic -c /etc/tuic/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF



}



start(){


            systemctl restart tuic
            systemctl status tuic

           echo "/etc/tuic/config.json" 
           cat "/etc/tuic/config.json" 

           # systemctl restart tuic4
           # systemctl status tuic4
           # systemctl restart tuic6
           # systemctl status tuic6
}

echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}tuic${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
            config
            downloadTuicCore
           start
            ;;
        2)
           systemctl status tuic
           echo "/etc/tuic/config.json" 
           cat "/etc/tuic/config.json" 
          # systemctl status tuic4
          # systemctl status tuic6
          # echo "/etc/tuic/config4.json" 
          # echo "/etc/tuic/config6.json" 
          # cat "/etc/tuic/config4.json" 
          # cat "/etc/tuic/config6.json" 
            ;;
	3)
systemctl restart tuic
systemctl status tuic
#systemctl restart tuic6
#systemctl status tuic6
;;

        00)
       exit
            ;;

esac
