#!/usr/bin/bash

apt install -y  dnsutils jq >/dev/null 2>&1

IPV4=$(curl -sSLk -4 ip.sb) >/dev/null 2>&1
#IPV4=dig  1.1.1.1 @8.8.4.4 +short

read -p 'ipdata.co; if Nothing input , this vps ip will be checked: ' IPV42


if  [ -z "$IPV42" ] ; then
      curl -sSLk "https://api.ipdata.co/$IPV4?api-key=513d4b07583037a5a89b6cff4ebff0083bef180977dc71dd73804cf8"|jq

     else
     #IPV42=$(ping  -4  -c 1 "${IPV42}"  |head -1 | awk '{print $3}'  | tr -d '(|)') >/dev/null 2>&1

     IPV42ip=$(dig  A "${IPV42}"    @1.1.1.1 +short)

         if [ -z "${IPV42ip}" ];then

     curl -sSLk  "https://api.ipdata.co/${IPV42}?api-key=513d4b07583037a5a89b6cff4ebff0083bef180977dc71dd73804cf8" |jq

else
     curl -sSLk  "https://api.ipdata.co/${IPV42ip}?api-key=513d4b07583037a5a89b6cff4ebff0083bef180977dc71dd73804cf8" |jq
        fi

fi
