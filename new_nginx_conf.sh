wget  -O /etc/nginx/nginx.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/_etc_nginx_nginx.conf
apt  install dnsutils -y
apt-get update -y
#apt-get install nginx -y
apt update  -y  
apt install nginx-extras  -y

mkdir -p  /home/rdp/Downloads/
mkdir -p  /data/ccaaDown/
mkdir -p  /etc/nginx/
mkdir -p  /etc/nginx/conf.d/
sed -i '10i\text/markdown           md markdown mkd ;'    /etc/nginx/mime.types


Un_Links() {

grep  ".sock\|.socket" /etc/nginx/conf.d/*.conf |xargs -I {}  echo {} |grep -v "#" |cut -d":" -f3 | tr -d ";"|cut -d" " -f1 |xargs -I {} unlink {}

#grep .socket /etc/nginx/conf.d/*.conf |grep grpc_pass  |xargs -I {}  echo {} |cut -d":" -f3 | tr -d ";" |xargs -I {} unlink {}
#grep  ".sock\|.socket" /etc/nginx/conf.d/*.conf |xargs -I {}  echo {} |grep -v "#" |cut -d":" -f3 | tr -d ";" |xargs -I {} unlink {}
}

Restart_Ng_under_links() {
systemctl reload nginx
systemctl restart nginx
systemctl stop nginx
Un_Links
systemctl restart nginx
systemctl status nginx
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
~/.acme.sh/acme.sh   --issue -d $Domain --keylength ec-256 --force  --standalone --listen-v6 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx" 

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



nginx_conf_func() {


Get_Key_Path

read -p "port  default: 9988: " Port
    if   [[ -z "$Port" ]]; then
            Port=9988

    fi




cat <<EOF > /etc/nginx/conf.d/${Port}.conf
server {
    listen $Port ; #ssl 
    listen [::]:$Port; #ssl
    server_name  $Domain;

    charset utf-8;
    root /usr/share/nginx/html;


#	ssl_certificate  $cer_path  ;
#	ssl_certificate_key  $key_path;
#	ssl_protocols TLSv1.2 TLSv1.3;
#	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
	
#	client_header_timeout 52w;
#        keepalive_timeout 52w;


#root  /root/Nginx-Fancyindex-Theme/fancyindex.conf ;



location /rdp {

    alias /home/rdp/Downloads/; 
    autoindex on;
autoindex_exact_size off;
autoindex_localtime on; 
}


location /ccaa {

    alias  /data/ccaaDown/;
    autoindex on;
autoindex_exact_size off;
autoindex_localtime on; 
}


location /f {
  
 alias  /root/d.share/;

autoindex on;
autoindex_exact_size off; 
autoindex_localtime on;     
charset utf-8,gbk;

#fancyindex on;
#fancyindex_localtime on;
#fancyindex_exact_size off;
#fancyindex_time_format "%Y-%m-%d %H:%M:%S";
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
 #include /root/Nginx-Fancyindex-Theme/ ;
    }
    
        location = /robots.txt {}
}

EOF





}








nginx_conf_func443() {


Get_Key_Path

read -p "port  default: 443: " Port
    if   [[ -z "$Port" ]]; then
            Port=443

    fi




cat <<EOF > /etc/nginx/conf.d/${Port}.conf
server {
    listen $Port ssl ;
    listen [::]:$Port ssl;
    server_name  $Domain;

    charset utf-8;
    #root /usr/share/nginx/html;


	ssl_certificate  $cer_path  ;
	ssl_certificate_key  $key_path;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
       
	client_header_timeout 52w;
        keepalive_timeout 52w;


#root  /root/Nginx-Fancyindex-Theme/fancyindex.conf ;



location /rdp {

    alias /home/rdp/Downloads/; 
    autoindex on;
autoindex_exact_size off;
autoindex_localtime on; 
}


location /ccaa {

    alias  /data/ccaaDown/;
    autoindex on;
autoindex_exact_size off;
autoindex_localtime on; 
}


location /f {
  
 alias  /root/d.share/;

autoindex on;
autoindex_exact_size off; 
autoindex_localtime on;     
charset utf-8,gbk;

#fancyindex on;
#fancyindex_localtime on;
#fancyindex_exact_size off;
#fancyindex_time_format "%Y-%m-%d %H:%M:%S";
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
 #include /root/Nginx-Fancyindex-Theme/ ;
    }
    
        location = /robots.txt {}
}

EOF





}















start_func(){

    systemctl daemon-reload
    systemctl reload  nginx
    systemctl restart nginx
netstat -ltnpu |grep nginx
    systemctl status nginx

}


echo -e "  ${GREEN}1.${PLAIN} 安装 ${BLUE}new_nginx_conf.sh${PLAIN}"
echo -e "  ${GREEN}443.${PLAIN} 安装 ${BLUE}nginx_conf_func443 ${PLAIN}"
echo -e "  ${GREEN}2.${PLAIN} 查看 ${BLUE}config${PLAIN}"
echo -e "  ${GREEN}3.${PLAIN} restart ${BLUE}Restart_Ng_under_links${PLAIN}"
echo -e "  ${GREEN}4.${PLAIN}  ${RED}check docker command${PLAIN}"
echo -e "  ${GREEN}00.${PLAIN} ${BLUE}exit${PLAIN}"


read -p " 选择：" answer
    case $answer in
        1)
	    nginx_conf_func
wget  -O /etc/nginx/nginx.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/_etc_nginx_nginx.conf
            start_func
            ;;
        443)
	    nginx_conf_func443
wget  -O /etc/nginx/nginx.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/_etc_nginx_nginx.conf
            start_func
            ;;
        2)
	   ls -lt /etc/nginx/conf.d
           systemctl status nginx
            ;;
	3)
Restart_Ng_under_links
;;
	4)
curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/new_nginx_conf.txt.sh
		;;
        00)
       exit
            ;;

esac

