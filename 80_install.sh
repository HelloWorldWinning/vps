wget --no-check-certificate -O /etc/nginx/conf.d/80.conf 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/80.conf'

read -p "输入nginx80监听port默认80:" port80 
if   [[ -z "$port80" ]]; then
        port80=80
fi

read -p "输入ws to vless port default 11180:" port5580 
if   [[ -z "$port5580" ]]; then
        port5580=11180
fi

read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
echo "必须输入 domain"
fi
read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
echo "必须输入 domain"
fi
read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
echo "必须输入 domain"
fi
read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
echo "必须输入 domain"
fi
read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
echo "必须输入 domain"
fi
read -p "输入domain:" DOmain
if   [[ -z "$DOmain" ]]; then
exit 1
fi
#####

read -p "输入ws path default xray :" Xray
if   [[ -z "$Xary" ]]; then
	     Xray="xray"
fi

sed -i "s/port80/${port80}/g"    /etc/nginx/conf.d/80.conf
sed -i "s/port5580/${port5580}/g"  /etc/nginx/conf.d/80.conf
sed -i "s/deldomain/${DOmain}/g"  /etc/nginx/conf.d/80.conf
sed -i "s/xray/${Xray}/g"  /etc/nginx/conf.d/80.conf


systemctl  restart nginx
systemctl  status  nginx
