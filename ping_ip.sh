#!/usr/bin/bash

IPV4=$(curl -4 ip.sb)
read -p 'https://www.boce.com/ping/;if Nothing input,this vps ip will be checked:' IPV42
if  [ -z "$IPV42" ] ; then
      
echo $IPV4

resulte_id=$(curl "https://api.boce.com/v3/task/create/ping?key=5061ff89a104e28fa6c9f434200a4e8a&node_ids=134,50,44,20,164,163,162&host=$IPV4" |  jq -r  '.data|.id')
echo $resulte_id

get_result=$(echo "https://api.boce.com/v3/task/ping/$resulte_id?key=5061ff89a104e28fa6c9f434200a4e8a")
echo $get_result

curl $get_result
sleep 15
curl $get_result | jq 'del(.. | .report_source?)'
 
else

echo $IPV42

resulte_id=$(curl "https://api.boce.com/v3/task/create/ping?key=5061ff89a104e28fa6c9f434200a4e8a&node_ids=164,163,162&host=$IPV42" |  jq -r  '.data|.id')
echo $resulte_id

get_result=$(echo "https://api.boce.com/v3/task/ping/$resulte_id?key=5061ff89a104e28fa6c9f434200a4e8a")
echo $get_result

curl $get_result
sleep 15
curl $get_result | jq 'del(.. | .report_source?)'
fi
