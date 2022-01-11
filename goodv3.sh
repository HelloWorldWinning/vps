#!/usr/bin/bash

# apt-get install wget 

ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)'

open_ipv6='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/open_ipv6.sh)'

xui='bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)'

ss_rust='wget -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && bash ss-plugins.sh'

nfFree='wget -N https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh [option] [lisence]'
nf_free2='wget -N https://cdn.jsdelivr.net/gh/kkkyg/CFwarp/CFwarp.sh && bash CFwarp.sh'
nf_free3='bash <(curl -fsSL git.io/warp.sh) menu'

#nfFree='bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/a.sh)'

nf='bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)'

s5='wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && chmod +x gost.sh && ~/gost.sh'


dd_oracle='bash <(wget --no-check-certificate -qO- 'https://moeclub.org/attachment/LinuxShell/InstallNET.sh') -d 11 -v 64 -a -p  1'
dd_1='wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh'

dd='apt update -y && apt dist-upgrade -y ; wget --no-check-certificate -O AutoReinstall.sh https://d.02es.com/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh'

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

wg_after_warp=' wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0  && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service  && systemctl enable wg-quick@wg0.service'

wg_for_oracle='wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_enp0s3.conf && wg-quick up wg0  ; wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_enp0s3.conf ; wg-quick up wg1; systemctl enable wg-quick@wg1.service  ; systemctl enable wg-quick@wg0.service'

openvpn='bash <(curl -sL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh )'
v2ray='bash <(curl -s -L https://git.io/v2ray.sh)'
kcptun='wget --no-check-certificate https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh &&chmod +x ~/kcptun.sh &&bash ~/kcptun.sh'
ss_go='wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh && chmod +x ss-go.sh && bash ss-go.sh'
 


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
11 dd  aws  ,甲骨文, 用默(DHCP) , , GCP 子网掩码mask 255.255.255.0
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
23 先 warp 再 wg
24 ipv4 v6转发
25 xray 换统一的uuid 并且 重启
26 安装   wget curl vim tree lsof  sudo htop
27 dd后 新建 ~/.ssh,覆盖安装 ~/.ssh/authorized_keys rsa 
28 wg 甲骨文网卡enp0s3专用 
29 dd甲骨文 debian 11 密码是:1

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
		23) eval $wg_after_warp;eval $ipv4_v6_forwarding;;
		24) eval $ipv4_v6_forwarding;;
		25)(sed -i 's/\w\{8\}\-\w\{4\}\-\w\{4\}\-\w\{4\}\-\w\{12\}/12345678-1234-1234-1234-123456789012/g'  /usr/local/etc/xray/config.json;echo 14 |eval $xray) ;;
		26)eval 'apt update;apt install wget curl vim tree lsof sudo htop' ;;
		27)eval  'mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys  ; systemctl restart sshd' ;;
		28)eval $wg_for_oracle;;
		29)eval $dd_oracle;;
		
		
		*) echo "wrong input" ;;
	esac
done
exit
