#!/usr/bin/bash

dd_debian11='bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 12 -v 64 -p "1" -port "54322"'


function getInterface(){
  interface=""
  Interfaces=`cat /proc/net/dev |grep ':' |cut -d':' -f1 |sed 's/\s//g' |grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn'`
  defaultRoute=`ip route show default |grep "^default"`
  for item in `echo "$Interfaces"`
    do
      [ -n "$item" ] || continue
      echo "$defaultRoute" |grep -q "$item"
      [ $? -eq 0 ] && interface="$item" && break
    done
  echo "$interface"
}


function netmask() {
  n="${1:-32}"
  b=""
  m=""
  for((i=0;i<32;i++)){
    [ $i -lt $n ] && b="${b}1" || b="${b}0"
  }
  for((i=0;i<4;i++)){
    s=`echo "$b"|cut -c$[$[$i*8]+1]-$[$[$i+1]*8]`
    [ "$m" == "" ] && m="$((2#${s}))" || m="${m}.$((2#${s}))"
  }
  echo "$m"
}


  interface=`getInterface`
  iAddr=`ip addr show dev $interface |grep "inet.*" |head -n1 |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[0-9]\{1,2\}'`
  ipAddr=`echo ${iAddr} |cut -d'/' -f1`
  ipMask=`netmask $(echo ${iAddr} |cut -d'/' -f2)`
  ipGate=`ip route show default |grep "^default" |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' |head -n1`

  echo "ip:" $ipAddr
  echo "gateway:" $ipGate
  echo "mask:" $ipMask


 read -p "重点关注mask 默认DD进行，其他情况手工输入:" DD_GO
if   [[ -z "$DD_GO" ]]; then
         eval ${dd_debian11}
else
 read -p "输入内网ip:" DD_IP
 read -p "输入网关gate:" DD_GATE
 read -p "输入mask:" DD_MASK
echo "debian 12"
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 12 -v 64 -p "1" -port "54322"  --ip-mask ${DD_MASK}       --ip-gate ${DD_GATE}    --ip-addr  ${DD_IP}




#  echo "bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 11 -v 64 -p "1" -port "54322"  --ip-mask     --ip-gate  255.255.255.0    --ip-addr  "
fi



