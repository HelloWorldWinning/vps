================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
"template": "$(python_version=$(command -v python >/dev/null 2>&1 && python --version 2>&1 | awk '{print $2}' || echo ''); conda_env=$(echo $CONDA_DEFAULT_ENV); if [ -z \"$conda_env\" ] && [ -z \"$python_version\" ]; then exit; else echo \" ($conda_env,$python_version)\"; fi)"

 ex it  style
================================================================
https://www.dongvps.com/2023-05-22/naiveproxy一键脚本更新如何正确的使用naive/

# 安装 naive命令
curl   https://raw.githubusercontent.com/imajeason/nas_tools/main/NaiveProxy/do.sh | bash
# 执行naive
naive

================================================================
Private key: YAjoKYIZ601zDTrYJKGoibA0bNTKCboCJNGUH7wgdn4
Public key: N9IY9bJiPgpe_1exP9LGkNHhqmbBL4tDbXc0lQEr9z8

https://github.com/zxcvos/Xray-script
Xray-REALITY 管理脚本
wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh


================================================================
优选WARP的EndPoint IP
https://github.com/getsomecat/GetSomeCats/blob/Surge/优选WARP的EndPoint%20IP，提高本地WARP节点访问性、修改官方客户端的EndPoint%20IP以及解锁ChatGPT.md
Linux 各发行版
wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-yxip/warp-yxip.sh && bash warp-yxip.sh

================================================================

https://github.com/P3TERX/warp.sh
Cloudflare WARP 一键安装脚本 使用教程
https://p3terx.com/archives/cloudflare-warp-configuration-script.html

================================================================
root@ja:/etc/wireguard# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 42:01:0a:b8:00:02 brd ff:ff:ff:ff:ff:ff
    altname enp0s4
    inet 10.184.0.2/24 brd 10.184.0.255 scope global ens4
       valid_lft forever preferred_lft forever
    inet6 fe80::4001:aff:feb8:2/64 scope link 
       valid_lft forever preferred_lft forever
8: warp: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none 
    inet 172.16.0.2/32 scope global warp
       valid_lft forever preferred_lft forever
    inet6 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128 scope global 
       valid_lft forever preferred_lft forever

root@ja:/etc/wireguard# cat warp.conf 
[Interface]
PrivateKey = +FGIX0vqalEDHX/dPUdYp9FCTKlHPiqoG7WC3kaGYl0=
Address = 172.16.0.2/32
Address = 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128
DNS = 1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844
MTU = 1420
PostUp = ip -4 rule add from 10.184.0.2 lookup main
PostDown = ip -4 rule delete from 10.184.0.2 lookup main

#Reserved = [164, 231, 38]
#Table = off
#PostUp = /etc/wireguard/NonGlobalUp.sh
#PostDown = /etc/wireguard/NonGlobalDown.sh

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0
#AllowedIPs = ::/0
Endpoint = 162.159.195.228:2371
PersistentKeepalive = 30

先wgcf 后 wg


PostUp =   iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o warp -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o warp -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o warp -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o warp -j MASQUERADE

================================================================
