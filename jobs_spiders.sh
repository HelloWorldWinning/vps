#!/usr/bin/bash

mkdir /root/job_2021
apt install -y aptitude
aptitude install  -y chromium-driver  msmtp mutt


cat >>~/.bashrc <<EOF
export PATH="/root/anaconda3/bin:$PATH"
EOF
source ~/.bashrc 


version=$(curl https://repo.anaconda.com/archive/ |grep Linux-x86_64.sh|cut -d">" -f2|cut -d'"' -f2  |head -1)
URL=$(echo "https://repo.anaconda.com/archive/$version")
#echo $URL


#wget -O /root/Anaconda3-2022.05-Linux-x86_64.sh https://repo.anaconda.com/archive/Anaconda3-2022.05-Linux-x86_64.sh
#wget -O /root/Anaconda-Linux-x86_64.sh           https://repo.anaconda.com/archive/Anaconda3-2022.10-Linux-x86_64.sh
wget -O /root/Anaconda3-Linux-x86_64.sh     "${URL}"      
bash    /root/Anaconda3-Linux-x86_64.sh

pip install  html5lib selenium



 

cat >>/root/.msmtprc <<EOF
tls on
tls_starttls on
tls_certcheck off
protocol smtp
auth on

#account gmail
host smtp.gmail.com
domain gmail.com
port 587
logfile   ~/.msmtp.log
user work100100@gmail.com
from work100100@gmail.com
password vmxjjnvkhkhfdqsp
#password qiubojunKJL12345
#password mmamhaodrvokcvhc
#tls_trust_file /etc/ssl/certs/ca-certificates.crt
# account gmail

EOF
 


cat >>/root/.muttrc <<EOF
set editor="vim"
set sendmail="/usr/bin/msmtp"
set use_from=yes
set realname="work100100@gmail"
set from=work100100@gmail.com
set envelope_from=yes
set crypt_use_gpgme=no

EOF





################################################
#aptitude install  -y chromium-driver  msmtp mutt
#cat >>~/.bashrc <<EOF
#export PATH="/root/anaconda3/bin:$PATH"
#EOF
#source ~/.bashrc 
#pip install  html5lib selenium





/root/anaconda3/bin/pip  install python-telegram-bot --upgrade

rm /root/Anaconda3-Linux-x86_64.sh 
