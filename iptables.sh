systemctl stop firewalld.service
systemctl disable firewalld.service
setenforce 0
ufw disable
 
iptables -t nat -F
iptables -t mangle -F 
iptables -F
iptables -X
iptables -Z
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
netfilter-persistent save


echo  "https://raw.githubusercontent.com/HelloWorldWinning/vps/main/iptables.sh"

echo"
已经清空所有 规则，允许所有端口
非常好的iptables详解 规则 
https://www.jianshu.com/p/ee4ee15d3658

iptables -P INPUT ACCEPT  #   (DROP|ACCEPT)  默认是关的/默认是开的

/usr/sbin/iptables  -D INPUT  1
iptables -I INPUT -p udp --dport  53848 -j DROP
iptables -I INPUT -p udp --destination-port  53848 -j DROP

iptables -I INPUT -j ACCEPT 
 
iptables -I  INPUT -p tcp --dport 8090 -j ACCEPT  #插入在链的第一位置

iptables -A INPUT -p tcp --dport 20 -j ACCEPT  #追加到链的末尾

iptables -I INPUT -p udp --destination-port  53848 -j DROP

需要 iptables 规则来接受所有传入的流量
https://qa.1r1g.cn/superuser/ask/44412861/

iptables -P INPUT ACCEPT iptables 说明
http://blog.chinaunix.net/uid-31410005-id-5775932.html
"
