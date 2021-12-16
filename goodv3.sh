dd_1='wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh'

dd='wget --no-check-certificate -O AutoReinstall.sh https://d.02es.com/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh'

tcpx='wget -N --no-check-certificate "https://github.000060000.xyz/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh'
realm='wget -N --no-check-certificate https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh'
xray='bash <(curl -sL https://s.hijk.art/xray.sh)'
trojan='bash <(curl -sL https://s.hijk.art/trojan-go.sh)'
speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/oooldking/script/master/superbench.sh | bash'
wg='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh
chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s'
openvpn='bash <(curl -sL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh )'
v2ray='bash <(curl -s -L https://git.io/v2ray.sh)'
kcptun='wget --no-check-certificate https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh &&chmod +x ~/kcptun.sh &&bash ~/kcptun.sh'
ss_go='wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh && chmod +x ss-go.sh && bash ss-go.sh'
#select action  in "tcpx" "realm" "xray" "trojan" "speed" "wg" "openvpn" "v2ray" 
#do
#	echo $action
#	break
while true
do
read  -p "$(echo -e "请选择
1 tcpx
2 realm
3 xray
4 trojan
5 speed
6 wg
7 openvpn
8 v2ray 
9 kcptun
10 ss_go
11 dd
12 dd_1
" "
")" choose
	case $choose in
		1) eval $tcpx  ;;
		2) eval $realm ;;
		3) eval $xray;;
		4) eval $trojan;;
		5) eval $speed;;
		6) eval $wg;;
		7) eval $openvpn;;
		8) eval $v2ray;;
		9) eval $kcptun;;
		10) eval $ss_go;;
		11) eval $dd;;
		12) eval $dd_1;;
		*) echo "wrong input" ;;
	esac
done
exit
