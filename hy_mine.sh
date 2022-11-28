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

      if [[ -f $cer_path ]]  && [[ -f $key_path ]]  ; then
    	echo $cer_path
    	echo $key_path
      else

	echo  "/root/.acme.sh/${Domain}_ecc/ 不存在cer key"	
	exit 1

      fi
fi


}








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

#sed -i 's/User=hysteria/User=root/g'  /./usr/lib/systemd/system/hysteria-server@.service
#sed -i 's/User=hysteria/User=root/g'  /./usr/lib/systemd/system/hysteria-server.service
#systemctl daemon-reload



function optimization_udp_tcp() {

echo 20240000 > /proc/sys/fs/file-max


	cat <<EOF >>  /etc/sysctl.conf 
net.core.rmem_default = 2097152
net.core.rmem_max = 8000000

net.core.wmem_default = 2097152
net.core.wmem_max = 5242880

net.ipv4.tcp_mem = 65536  393216  524288
net.ipv4.tcp_rmem = 1048576  2097152  5242880
net.ipv4.tcp_wmem = 1048576  2097152  5242880
EOF

sysctl -p

	 
}




mkdir -p /etc/hy/


cat <<EOF >/./usr/lib/systemd/system/hy.service
[Unit]
Description=Hysteria, a feature-packed network utility optimized for networks of poor quality
Documentation=https://github.com/HyNetwork/hysteria/wiki
After=network.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
WorkingDirectory=/etc/hysteria
Environment=HYSTERIA_LOG_LEVEL=info
ExecStart=/usr/local/bin/hysteria -c /etc/hy/config.json server
Restart=on-failure
RestartPreventExitStatus=1
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


function  install_config_hy(){

bash  <(curl -Ls https://raw.githubusercontent.com/HyNetwork/hysteria/master/install_server.sh)

Get_Key_Path


#while true
#        do
#            read -p " 请输入cer path：" cert_path
#            if [ ! -f "${cert_path}" ]; then
#                echoColor red " certificate path wrong，请重新输入！"
#				echoColor green "请输入证书cert文件路径(需fullchain):"
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
#				echoColor green "请输入证书key文件路径(需fullchain):"
#            else
#                break
#            fi
#        done
#
#
#



read -p "listen Port default(44444)
: " Listen_Port
    if   [[ -z "$Listen_Port" ]]; then
            Listen_Port=44444

    fi


read -p "QUIC connection receive window recv_window_client default(67108864) 
: " recv_window_client
    if   [[ -z "$recv_window_client" ]]; then
            recv_window_client=67108864

    fi


read -p "QUIC stream receive window recv_window_conn default(16777216) 
: " recv_window_conn
    if   [[ -z "$recv_window_conn" ]]; then
            recv_window_conn=16777216

    fi

#echo "Listen_Port" $Listen_Port
#echo "recv_window_client" $recv_window_client
#echo "recv_window_conn" $recv_window_conn
#echo "cert_path" $cert_path
#echo "key_path" $key_path
 
	cat <<EOF > /etc/hy/config.json
{
"listen": ":$Listen_Port",
"protocol": "wechat-video",
"disable_udp": false,
"cert": "$cert_path",
"key":  "$key_path",
"obfs": "love me",
"auth": {
	"mode": "password",
	"config": {
	"password": "1"
	}
},
"alpn": "h3",
"recv_window_conn":   $recv_window_conn,
"recv_window_client": $recv_window_client,
"max_conn_client": 4096,
"disable_mtu_discovery": true,
"resolve_preference": "46",
"resolver": "https://dns.google/dns-query"
}
EOF

 echo "/etc/hy/config.json" 
 cat "/etc/hy/config.json" 

 

 systemctl daemon-reload
 systemctl enable hy
 systemctl start hy

systemctl  restart hy
systemctl  status hy

}




echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}hysteria${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"




read -p " 选择：" answer
    case $answer in
        1)
           optimization_udp_tcp
            install_config_hy
            ;;
        2)
           echo "/etc/hy/config.json" 
           cat "/etc/hy/config.json" 
systemctl  status hy
   
            ;;
	3)
systemctl  restart hy
systemctl  status hy
;;

        00)
       exit
            ;;

esac


