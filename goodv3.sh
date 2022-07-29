#!/usr/bin/bash

Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"

net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)


# apt-get install wget 
# 26)eval 'apt update;apt install -y wget curl vim tree lsof sudo htop rsync screen jq net-tools telnet' ;;



dd_debian11='bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 11 -v 64 -p "1" -port "54322"'

xray_mianliu='bash <(curl -fsSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_mianliu.sh)'


trojan_go_mianliu='bash <(curl -fsSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan_go_mianliu.sh)'

tcpx121721='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcp131721.sh)'

jobs_spiders='wget --no-check-certificate -O ~/jobs_spiders.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jobs_spiders.sh   && chmod +x ~/jobs_spiders.sh  && ~/jobs_spiders.sh && source ~/.bashrc  '


ping_local='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_local.sh)'



superspeed_uxh='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/superspeed_uxh.sh)'


hysteria='bash <(curl -fsSL https://git.io/hysteria.sh)'


delete_user='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/delete_user.sh)'

rdp='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/rdp.sh)'





ss_rust='wget -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && ./ss-plugins.sh'

Linux_tools='wget -N --no-check-certificate https://raw.githubusercontents.com/Misaka-blog/MisakaLinuxToolbox/master/MisakaToolbox.sh && bash MisakaToolbox.sh'

 
iptables_rules='bash <(curl -sL   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/iptables.sh)'
 
disable_all_wg_servers='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/disable_all_wg_servers.sh)'


latest_arm_kernel='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/latest_arm_kernel.sh)'


debian_tools='source <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/debian_tools ) '

bashrc='source <(curl -sL   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/bashrc ) '


jupyter_notebook_remote_access='bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter_notebook_remote_access.sh)'

install_docker_ccaa='bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_ccaa.sh)'


install_docker='bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker.sh)'

ping_ip='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_ip.sh)'

isp_checker2='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/isp_checker)'

bierendegongju='wget -O jcnfbox.sh https://raw.githubusercontent.com/Netflixxp/jcnf-box/main/jcnfbox.sh && chmod +x jcnfbox.sh && clear && ./jcnfbox.sh'

update_Aria2='crontab -l > conf && echo  -e "* */4 * * *   bash /etc/ccaa/upbt.sh >> /tmp/tmp.txt" >> conf && crontab conf && rm -f conf'

Aria2='bash <(curl -Lsk https://raw.githubusercontent.com/helloxz/ccaa/master/ccaa.sh)'

isp_ip='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/isp_ip.sh)'

ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)'

oc_ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/oc_ip_forwarding.sh)'


open_ipv6='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/open_ipv6.sh)'

xui='bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)'

ss_rust='wget -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && bash ss-plugins.sh'

nfFree='wget -N https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh [option] [lisence]'
nf_free2='wget -N https://cdn.jsdelivr.net/gh/kkkyg/CFwarp/CFwarp.sh && bash CFwarp.sh'
nf_free3='bash <(curl -fsSL git.io/warp.sh) menu'

#nfFree='bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/a.sh)'

nf='bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)'

s5='wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && chmod +x gost.sh && ~/gost.sh'


# dd_oracle='bash <(wget --no-check-certificate -qO- 'https://moeclub.org/attachment/LinuxShell/InstallNET.sh') -d 11 -v 64 -a -p  1'


dd_oracle='bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/dd_oracle_arm.sh') -d 11 -v 64 -a -p  1'

# dd_1='wget --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh'

dd_1='wget --no-check-certificate -O AutoReinstall.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/AutoReinstall2.sh && bash AutoReinstall.sh'

dd='wget --no-check-certificate -O AutoReinstall.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh'

tcpx='wget -N --no-check-certificate "https://github.000060000.xyz/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh'
realm='wget -N --no-check-certificate https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh'
xray='bash <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xrayMINE)'
# xray='bash <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_vless.sh)'

#trojan='bash <(curl -sL https://s.hijk.art/trojan-go.sh)'

trojan='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan-go.sh)'

# speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/oooldking/script/master/superbench.sh | bash'

speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/HelloWorldWinning/vps/main/speed5.sh | bash'
# speed2='bash <(curl -Lso- https://git.io/Jlkmw)'
speed2='bash <(curl -Lso-  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/speed17.sh)'
speed3='wget -qO- bench.sh | bash'


# wg='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -r && bash  ~/wireguard.sh  -u && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf &&  sed -i 's/eth0/${net_card}/g'  /etc/wireguard/wg0.conf   &&wg-quick up wg0 && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf && sed -i 's/eth0/${net_card}/g'  /etc/wireguard/wg1.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'

wg='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && bash  ~/wireguard.sh  -u && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf &&  sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg0.conf   &&wg-quick up wg0 && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf && sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg1.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service;  wget -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf && sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg2.conf && wg-quick up wg2 && systemctl enable wg-quick@wg2.service'

wg_to_wgcf='wget --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0 && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'

wg_after_warp=' wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0  && wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service  && systemctl enable wg-quick@wg0.service'

wg_for_oracle='wget -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_enp0s3.conf && wg-quick up wg0  ; wget -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_enp0s3.conf ; wg-quick up wg1; systemctl enable wg-quick@wg1.service  ; systemctl enable wg-quick@wg0.service'

openvpn='bash <(curl -sL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh )'
v2ray='bash <(curl -s -L https://git.io/v2ray.sh)'
kcptun='wget --no-check-certificate https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh &&chmod +x ~/kcptun.sh &&bash ~/kcptun.sh'
ss_go='wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh && chmod +x ss-go.sh && bash ss-go.sh'
ss_latest='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ss.sh)'
ssr='wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ssr.sh && chmod +x ssr.sh && bash ssr.sh'
 


while true
do
read  -p "$(echo -e "请选择

${Red_font_prefix}1${Font_color_suffix} tcpx
${Red_font_prefix}2${Font_color_suffix} trojan
${Red_font_prefix}3${Font_color_suffix} xray
${Red_font_prefix}4${Font_color_suffix} realm 中转用
${Red_font_prefix}5${Font_color_suffix} speedtest of vps
${Red_font_prefix}6${Font_color_suffix} wg
${Red_font_prefix}7${Font_color_suffix} openvpn
${Red_font_prefix}8${Font_color_suffix} v2ray
${Red_font_prefix}9${Font_color_suffix} kcptun
${Red_font_prefix}10${Font_color_suffix} ss_go
${Red_font_prefix}11o${Font_color_suffix} dd  aws/aws windows   ,甲骨文, 用默(DHCP) , , GCP 子网掩码mask 255.255.255.0
${Red_font_prefix}11${Font_color_suffix} MoeClub InstallNET.sh
${Red_font_prefix}12${Font_color_suffix} dd_1 azure用默认
${Red_font_prefix}13${Font_color_suffix} s5 socks5代理用
${Red_font_prefix}14${Font_color_suffix} netflix available test
${Red_font_prefix}15${Font_color_suffix} nf freedom
${Red_font_prefix}16${Font_color_suffix} ss_rust
${Red_font_prefix}17${Font_color_suffix} speed2   of vps 全网/三网
${Red_font_prefix}18${Font_color_suffix} wg to wgcf 有wgcf 解锁nf 情况用
${Red_font_prefix}19${Font_color_suffix} x ui 面板
${Red_font_prefix}20${Font_color_suffix} open ipv6
${Red_font_prefix}21${Font_color_suffix} 甬哥 netflix free
${Red_font_prefix}22${Font_color_suffix} P3terx  netflix free
${Red_font_prefix}23${Font_color_suffix} 先 warp 再 wg
${Red_font_prefix}24${Font_color_suffix} ipv4 v6转发
${Red_font_prefix}25${Font_color_suffix} xray 换统一的uuid 并且 重启
${Red_font_prefix}26${Font_color_suffix} 安装   wget curl vim tree lsof  sudo htop rsync screen jq net-tools
${Red_font_prefix}27${Font_color_suffix} dd后. /etc/ssh/sshd_config  systemctl restart sshd 新建 ~/.ssh,覆盖安装
${Red_font_prefix}28${Font_color_suffix} wg 甲骨文网卡enp0s3专用
${Red_font_prefix}29${Font_color_suffix} dd甲骨文 debian 11 密码是:1
${Red_font_prefix}30${Font_color_suffix} 秋水逸冰大佬的写的Bench.sh脚本
${Red_font_prefix}31${Font_color_suffix} s.hijk.art的最新ss脚本
${Red_font_prefix}32${Font_color_suffix} ssr 多用户脚本
${Red_font_prefix}33${Font_color_suffix} isp ipdata.co check
${Red_font_prefix}34${Font_color_suffix} 网盘 Aria2秘密安装时候设定。ccaa:进入CCAA操作界面 ；文件管理默认用户名为ccaa，密码为admin，登录后可在后台修改
${Red_font_prefix}35${Font_color_suffix} 自动更新${Red_font_prefix}34${Font_color_suffix}的Aria2，bash /etc/ccaa/upbt.sh >> /tmp/tmp.txt
${Red_font_prefix}36${Font_color_suffix} 甲骨文 ipv4 v6转发 enp0s3网卡
${Red_font_prefix}37${Font_color_suffix} 别人的vps 工具包 
${Red_font_prefix}38${Font_color_suffix} https://www.ip2location.com/ check
${Red_font_prefix}39${Font_color_suffix} https://www.boce.com/ping/  | jq 'del(.. | .report_source?)'
${Red_font_prefix}40${Font_color_suffix} sysctl -p /etc/sysctl.conf
${Red_font_prefix}41${Font_color_suffix} install docker
${Red_font_prefix}42${Font_color_suffix} install_docker_ccaa
${Red_font_prefix}43${Font_color_suffix} wget bashrc 。手工输入  source  ~/.bashrc
${Red_font_prefix}44${Font_color_suffix} enable jupyter_notebook_remote_access  jupyter notebook   --port=16666 --ip 0.0.0.0 --no-browser --allow-root
${Red_font_prefix}45${Font_color_suffix} 升级到最新的 armv8 debian系统
${Red_font_prefix}46${Font_color_suffix} systemctl stop wg-quick@${wg_i} systemctl disable wg-quick@${wg_i}   systemctl stop and disable all wg
${Red_font_prefix}47${Font_color_suffix} iptables -P  INPUT/OUTPUT/FORWARD  ACCEPT
${Red_font_prefix}48${Font_color_suffix} Linux VPS tools
${Red_font_prefix}49${Font_color_suffix} shadowrocket rust + many plugins(kcptun...)
${Red_font_prefix}50${Font_color_suffix} eval "netstat -lpntu"
${Red_font_prefix}tt${Font_color_suffix} "read -p "script to run ":  ${x}"
${Red_font_prefix}56${Font_color_suffix} (amd64)一键安装 远程桌面 echo xfce4-session>/home/<rdp_username>/.xsession ; sudo service xrdp stop /status
${Red_font_prefix}57${Font_color_suffix} delete user  'getent passwd | awk -F: '{ print \$1}'|sort'
${Red_font_prefix}58${Font_color_suffix} bash <(curl -fsSL https://git.io/hysteria.sh)
${Red_font_prefix}59${Font_color_suffix} superspeed_uxh.sh 
${Red_font_prefix}60${Font_color_suffix} ping_local
${Red_font_prefix}61${Font_color_suffix} 一键工作爬虫搞定 source ~/.bashrc 
${Red_font_prefix}2137${Font_color_suffix} 一键搞定13 17 21,需要reboot
${Red_font_prefix}62${Font_color_suffix} trojan_go ws ${Red_font_prefix}免流${Font_color_suffix}
${Red_font_prefix}63${Font_color_suffix} xray ${Red_font_prefix}免流${Font_color_suffix}


${Red_font_prefix}00${Font_color_suffix} exit

sed -i 's/eth0/enp0s3/g'  /etc/sysctl.conf 
nohup command > /dev/null 2>&1 &
hostnamectl set-hostname
 

\r\n
")" choose
	case $choose in
		1) eval $tcpx  ;;
		2) eval $trojan ;;
		3) eval $xray;;
		4) eva $realml;;
		5) eval $speed;;
		6) eval $wg ; eval $ipv4_v6_forwarding;;
		7) eval $openvpn;;
		8) eval $v2ray;;
		9) eval $kcptun;;
		10) eval $ss_go;;
		11o) eval $dd;;
		11) eval $dd_debian11;;
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
		
		26)eval "$debian_tools";;
		27)eval  'rm -fr  ~/.ssh ;mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys; sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g"  /etc/ssh/sshd_config;sed -i "s/#Port 22/Port 54322/g"  /etc/ssh/sshd_config ;sed -i "s/Port 22/Port 54322/g"  /etc/ssh/sshd_config ; sed -i "s/PermitRootLogin no/PermitRootLogin yes/g"  /etc/ssh/sshd_config ; systemctl restart sshd' ;;		
		28)eval $wg_for_oracle;;
		29)eval $dd_oracle;;
		30)eval $speed3;;
		31)eval $ss_latest;;
		32)eval $ssr;;
		33)eval $isp_ip;;
		34)eval $Aria2;;
		35)eval "$update_Aria2";;
		36)eval "$oc_ipv4_v6_forwarding";;
		37)eval "$bierendegongju";;
		38)eval "$isp_checker2";;
		39)eval "$ping_ip";;		
		40)eval 'sysctl -p /etc/sysctl.conf';;	
		41)eval $install_docker;;
		42)eval $install_docker_ccaa;;
		43)eval "$bashrc";;
		44)eval "$jupyter_notebook_remote_access";;
		45)eval "$latest_arm_kernel";;
		46)eval "$disable_all_wg_servers";;
		47)eval "${iptables_rules}";;
		48)eval "$Linux_tools";;
		49)eval "$ss_rust";;
		50)eval "sudo netstat -lpntu";;
                tt)read -p 'script to run': x && ${x};;
                56)eval "$rdp";;
                57)eval "$delete_user";;
                58)eval "$hysteria";;
                59)eval "$superspeed_uxh | tee speeds.log";;		
                60)eval "$ping_local";;		
                61)eval "$jobs_spiders" ;;		
                2137)eval "$tcpx121721" ;;
                62)eval "$trojan_go_mianliu" ;;
                63)eval "$xray_mianliu" ;;
		
		00)eval "exit";;
		
		*) echo "wrong input" ;;
	esac

read -p 'time to go': seconds ;
[[ -z "${seconds}" ]] && seconds=0
sleep ${seconds}

done
exit
