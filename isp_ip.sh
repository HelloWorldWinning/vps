#!/usr/bin/bash

IPV4=$(curl -4 ip.sb)
read -p 'input ip; if Nothing input , this vps ip will be checked  : ' IPV42

if  [ -z "$IPV42" ] ; then
      curl "https://api.ipdata.co/$IPV4?api-key=513d4b07583037a5a89b6cff4ebff0083bef180977dc71dd73804cf8"|jq

     else

     curl "https://api.ipdata.co/$IPV42?api-key=513d4b07583037a5a89b6cff4ebff0083bef180977dc71dd73804cf8" |jq

fi
