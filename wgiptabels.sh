apt-get install iptables-persistent -y
iptables-save -f /etc/iptables/rules.v4
ip6tables-save -f /etc/iptables/rules.v6


crontab -l > conf && echo  -e "@reboot iptables-restore < /etc/iptables/rules.v4" >> conf && crontab conf && rm -f conf

crontab -l > conf && echo  -e "@reboot ip6tables-restore < /etc/iptables/rules.v6" >> conf && crontab conf && rm -f conf


