all_wg=$(ps aux|grep  wg-crypt-wg |grep "\["  | tail -n +2|  awk '{print $NF}' | cut -d "-" -f 3|cut -d "]" -f 1)

for wg_i in $all_wg
do
  (
  echo " systemctl stop and disable:"
  echo ${wg_i}
  systemctl stop wg-quick@${wg_i}
  systemctl disable wg-quick@${wg_i}
  )
  
done
