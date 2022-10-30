site=(
"doeasy.ml"
"doeasy.cf"
"doeasy.tk"
"doeasy.gq"
"az.wardao.xyz"
"wardao.xyz"
"hk.wardao.xyz"
"del.wardao.xyz"
)


site6=(
"6.doeasy.ml"
"6.doeasy.cf"
"61.doeasy.gq"
"62.doeasy.gq"
"6.wardao.xyz"
"6t.doeasy.cf"
)


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



n=50

#read -p "ping n default 5=>" n
#if [[ -z "${n}" ]]; then
#	    	 n=5
#fi

##########



#out=$(echo "${site6[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping6 {}  -c ${n} )
out=$(echo "${site6[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 sudo ping6 {} -l 50  -c ${n} )

sites_out=$(echo "$out" |grep  statistics |cut -d " " -f2)
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
  echo -e "${Red}${av}${NC} ${Blue}${loss_out[$i]}${NC} ${stat_out[$i]} ${sites_out[$i]}"
done



##########

echo "##############"

#ehco "${site[*]}"
#echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping  -c ${n} {}

#out=$(echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 ping  -c ${n} {})
out=$(echo "${site[@]}" | tr " " "\n"  | xargs -n 1 -I {} -P 0 sudo  ping -l 50 -c ${n} {})

sites_out=$(echo "$out" |grep  statistics |cut -d " " -f2)
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
  echo -e "${Red}${av}${NC} ${Blue}${loss_out[$i]}${NC} ${stat_out[$i]} ${sites_out[$i]}"
done
