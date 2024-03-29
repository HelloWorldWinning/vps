#read -p "ping n default 5=>" n
#[[ -z "${n}" ]] && n=5 
####################if [[ -z "${n}" ]]; then n=5 fi
n=4
#site=(
#"jp2a.jingyi.today"
#"jp2b.jingyi.today"
#"jp2c.jingyi.today"
#
#)

#echo "Enter the list of IPs or domains separated by space:"
#read -a site

# Reading the list of IPs or domains
# Initialize the site array
declare -a site

# Reading the list of IPs or domains
echo "Enter the list of IPs or domains line by line:"

#echo "(press ENTER  2222222222  to end input):"
while IFS= read -r line; do
    if [ -z "$line" ]; then
        break
    fi
    site+=("$line")
done

#while IFS= read -r line || [[ -n "$line" ]]; do
#    if [ -z "$line" ]; then
#        break
#    fi
#    site+=("$line")
#done


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

#ip=$(dig +time=2  +short A ${sites_out[$i]} @1.1.1.1 |head -1)
ip=$(dig +time=2  +short A ${sites_out[$i]} @1.1.1.1 )

  echo -e "  ${Red}${av}${NC} ${Blue}${loss_out[$i]}${NC} ${stat_out[$i]} ${sites_out[$i]} $ip "
done

