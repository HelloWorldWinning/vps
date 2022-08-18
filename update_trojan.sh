crontab -l > conf && echo  -e "30 5 */7 * *   eval 'echo 3 | bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan-go.sh)' >/root/tmp_trojan.txt" >> conf && crontab conf && rm -f conf
 #crontab -l > conf && echo  -e "*/1 * * * *   eval 'echo 3 \| bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan-go.sh)' >/root/tmp_trojan.txt" >> conf && crontab conf && rm -f conf

cat  >> /etc/resolv.conf<<EOF 
nameserver 8.8.4.4
nameserver 8.8.8.8
nameserver 2001:4860:4860::8844
nameserver 2001:4860:4860::8888
EOF

inet_ip=$(cat  /etc/hosts|grep debian |awk '{print $1}')
cat  >> /etc/hosts<<EOF 
${inet_ip} $HOSTNAME
EOF
