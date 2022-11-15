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

sed -i 's/User=hysteria/User=root/g'  /./usr/lib/systemd/system/hysteria-server@.service
sed -i 's/User=hysteria/User=root/g'  /./usr/lib/systemd/system/hysteria-server.service

function  install_config_hy(){

bash  <(curl -Ls https://raw.githubusercontent.com/HyNetwork/hysteria/master/install_server.sh)

while true
        do
            read -p " 请输入cer path：" cert_path
            if [ ! -f "${cert_path}" ]; then
                echoColor red " certificate path wrong，请重新输入！"
				echoColor green "请输入证书cert文件路径(需fullchain):"
            else
                break
            fi
        done

while true
        do
            read -p " 请输入key path：" key_path
            if [ !  -f "${key_path}" ]; then
                echoColor red " key path wrong，请重新输入！"
				echoColor green "请输入证书key文件路径(需fullchain):"
            else
                break
            fi
        done






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
 
	cat <<EOF > /etc/hysteria/config.json
{
"listen": ":$Listen_Port",
"protocol": "wechat-video",
"disable_udp": false,
"cert": "$cert_path",
"key":  "$key_path",
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

 echo "/etc/hysteria/config.json" 
 cat "/etc/hysteria/config.json" 

systemctl  restart hysteria-server
systemctl  status hysteria-server
 

}




echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}hysteria${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"




read -p " 选择：" answer
    case $answer in
        1)
            install_config_hy
            ;;
        2)
systemctl  status hysteria-server
           echo "/etc/hysteria/config.json" 
           cat "/etc/hysteria/config.json" 
   
            ;;
	3)
systemctl  restart hysteria-server
systemctl  status hysteria-server
;;

        00)
       exit
            ;;

esac


