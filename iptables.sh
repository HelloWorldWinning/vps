iptables -P INPUT ACCEPT  #   (DROP|ACCEPT)  默认是关的/默认是开的
/usr/sbin/iptables  -D INPUT  1


iptables -I INPUT -j ACCEPT 

iptables -I INPUT -j ACCEPT


iptables -I  INPUT -p tcp --dport 8090 -j ACCEPT  #插入在链的第一位置
iptables -A INPUT -p tcp --dport 20 -j ACCEPT  #追加到链的末尾

iptables -I INPUT -p udp --destination-port  53848 -j DROP

需要 iptables 规则来接受所有传入的流量
https://qa.1r1g.cn/superuser/ask/44412861/
