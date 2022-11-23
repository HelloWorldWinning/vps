site=(
"baidu.com"
"hk.hardeasy.top"
"hardeasy.top"
"tw.hardeasy.top"
"ali.hardeasy.top"
"azsg.hardeasy.top"
"azjp.hardeasy.top"
"awsjp.hardeasy.top"
"awssg.hardeasy.top"
"tokyo.hardeasy.top"
"sanjose.hardeasy.top"
"uloveme.eu.org"
"ulovem.eu.org"
)


site6=(
"6tokyo.hardeasy.top"
"6awssg.hardeasy.top"
"6awsjp.hardeasy.top"
"6.hardeasy.top"
"6hk.hardeasy.top"
"6tw.hardeasy.top"
"66sanjose.hardeasy.top"
)

IPV4_local=$(dig @ns1.google.com TXT o-o.myaddr.l.google.com +short -4 |tr -d \")
IPV6_local=$(dig @ns1.google.com TXT o-o.myaddr.l.google.com +short -6 |tr -d \")
echo "local Public IPV4 : $IPV4_local"
echo "local Public IPV6 : $IPV6_local"

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"

RED='\033[0;31m'
NC='\033[0m' # No Color

Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White



n=5

#read -p "ping n default 5=>" n
#if [[ -z "${n}" ]]; then
#	    	 n=5
#fi



echo "============ ipv6 ============"

out=$(echo "${site6[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping6 {}  -c ${n} )
#echo $out
#out=$(echo "${site6[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 sudo ping6 {} -l 50  -c ${n} )

sites_out=$(echo "$out" |grep  statistics |cut -d " " -f2)


#ip_out=$(echo "$out" |grep PING6)

#ip_out=$(echo "$out" |grep PING | awk '{print $3}' | tr -d '(|)|:')
ip_out=$(echo "$out" |grep PING | awk '{print $5}' )

#echo $ip_out

#exit 0

loss_out=$(echo "$out" |grep  transmitted |awk  '{print $(NF -2)}')
stat_out=$(echo "$out" |grep  max|awk '{print $(NF -1)}' |  sed "s/\.[0-9][0-9][0-9]//g")
#stat_out=$(echo "$out" |grep  std-dev|awk '{print $(NF -1)}' |  sed "s/\.[0-9][0-9][0-9]//g")

#stat_out=$(echo "$out" |grep  stddev| cut -d " " -f4   )
#cat "$stat_out"

#for ((i = 0; i < ${#sites_out[@]}; ++i)); do
#    # bash arrays are 0-indexed
#    # echo -e "${loss_out[$i]}" "${stat_out[$i]}"  "${sites_out[$i]}"
#     echo "$i"
#done
#echo $sites_out

sites_out=($sites_out)

#echo $sites_out
loss_out=($loss_out)
stat_out=($stat_out)
#

for i in ${!sites_out[@]}; do
  av="$(echo "${stat_out[$i]}"|cut -d "/" -f 2)"
  #ip="$(echo $ip_out|cut -d' ' -f  $(($i+1)) )"
ip=$(dig +time=2 +short AAAA  ${sites_out[$i]} @1.1.1.1 )
  echo -e "  ${Red}${av}${NC} ${Blue}${loss_out[$i]}${NC} ${stat_out[$i]} ${sites_out[$i]} $ip"
done



##########

echo "============ ipv4 ============"

#ehco "${site[*]}"
#echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping  -c ${n} {}

out=$(echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping  -c ${n} {})
#out=$(echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 sudo  ping -l 50 -c ${n} {})

sites_out=$(echo "$out" |grep  statistics |cut -d " " -f2)

ip_out=$(echo "$out" |grep PING | awk '{print $3}' | tr -d '(|)|:')

loss_out=$(echo "$out" |grep  transmitted |awk  '{print $(NF -2)}')
stat_out=$(echo "$out" |grep max|awk '{print $(NF -1)}' |  sed "s/\.[0-9][0-9][0-9]//g")
#stat_out=$(echo "$out" |grep  std-dev|awk '{print $(NF -1)}' |  sed "s/\.[0-9][0-9][0-9]//g")
#stat_out=$(echo "$out" |grep  stddev| cut -d " " -f4   )
#cat "$stat_out"

#for ((i = 0; i < ${#sites_out[@]}; ++i)); do
#    # bash arrays are 0-indexed
#    # echo -e "${loss_out[$i]}" "${stat_out[$i]}"  "${sites_out[$i]}"
#     echo "$i"
#done
#echo $sites_out
sites_out=($sites_out)
#echo $sites_out
loss_out=($loss_out)
stat_out=($stat_out)
#
for i in ${!sites_out[@]}; do
  av="$(echo "${stat_out[$i]}"|cut -d "/" -f 2)"
  #ip="$(echo $ip_out | cut -d' ' -f $i)"
#  ip="$(echo $ip_out|cut -d' ' -f  $(($i+1)) )" 
ip=$(dig +time=2  +short A ${sites_out[$i]} @1.1.1.1 |head -1)

  echo -e "  ${Red}${av}${NC} ${Blue}${loss_out[$i]}${NC} ${stat_out[$i]} ${sites_out[$i]} $ip "
done
