#! /bin/bash

# apt-get install wget 

open_ipv6='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/open_ipv6.sh)'

xui='bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)'

ss_rust='wget -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && bash ss-plugins.sh'

nfFree='wget -N https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh [option] [lisence]'
nf_free2='wget -N https://cdn.jsdelivr.net/gh/kkkyg/CFwarp/CFwarp.sh && bash CFwarp.sh'
nf_free3='bash <(curl -fsSL git.io/warp.sh) menu'

#nfFree='bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/a.sh)'

nf='bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)'

s5='wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && chmod +x gost.sh && ~/gost.sh'


dd_1='wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh'

dd='wget --no-check-certificate -O AutoReinstall.sh https://d.02es.com/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh'

tcpx='wget -N --no-check-certificate "https://github.000060000.xyz/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh'
realm='wget -N --no-check-certificate https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh'
xray='bash <(curl -sL https://s.hijk.art/xray.sh)'
# xray='bash <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_vless.sh)'

trojan='bash <(curl -sL https://s.hijk.art/trojan-go.sh)'

# trojan='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan-go.sh)'

speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/oooldking/script/master/superbench.sh | bash'
speed2='bash <(curl -Lso- https://git.io/Jlkmw)'


wg='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf && wg-quick up wg0 && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'

wg_to_wgcf='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0 && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'

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
2 realm 中转用
3 xray
4 trojan
5 speedtest of vps
6 wg
7 openvpn
8 v2ray 
9 kcptun
10 ss_go
11 dd  aws DHCP默认  , GCP 子网掩码mask 255.255.255.0
12 dd_1 azure用默认
13 s5 socks5代理用
14 netflix available test
15 nf freedom
16 ss_rust
17 speed2   of vps 全网/三网
18 wg to wgcf 有wgcf 解锁nf 情况用
19 x ui 面板 
20 open ipv6
21 甬哥 netflix free
22 P3terx  netflix free

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
		13) eval $s5;;
		14) eval $nf;;
		15) eval $nfFree;;
                16) eval $ss_rust;;
	        17) eval $speed2;;
	        18) eval $wg_to_wgcf;;
		19) eval $xui;;
		20) eval $open_ipv6;;
		21) eval $nf_free2;;
		22) eval $nf_free3;;
		
		
		*) echo "wrong input" ;;
	esac
done
exit
