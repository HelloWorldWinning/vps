wget --no-check-certificate -O /etc/nginx/conf.d/80.conf 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/80.conf'

read -p "输入nginx80监听port默认80:" port80 
if   [[ -z "$port80" ]]; then
        port80=80
fi

read -p "输入ws to vless port default 5580:" port5580 
if   [[ -z "$port5580" ]]; then
        port5580=5580
fi


sed -i "s/port80/${port80}/g"    /etc/nginx/conf.d/80.conf
sed -i "s/port5580/${port5580}/g"  /etc/nginx/conf.d/80.conf


systemctl  restart nginx
