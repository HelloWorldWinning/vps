#!/usr/local/bin/bash

SITES=(
"comment:GCP"
"uloveme.eu.org"
"g.wardao.xyz"

"comment:AZ"
"az.wardao.xyz"
"ajp.wardao.xyz"

"comment:AWS"
"jp.wardao.xyz"
"sg.wardao.xyz"
"sgec2.wardao.xyz"

"comment:others"
"ibm1.wardao.xyz"

)





Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"

# Error="${Red_font_prefix}[错误]${Font_color_suffix}"
 

#string_all="123222 32 232"
#string_unwanted="32"
#string_wanted=${string_all//$string_unwanted/}



read -p "ping n (default 3)=" PING_N_input
if   [[ -z "$PING_N_input" ]]; then
        n=3
else
n=${PING_N_input}
fi


 
for a_site in ${SITES[*]}; do
if [[ $a_site == *"comment"* ]]; then
  #echo "It's there!"
#  echo "comment:gcp" | cut -d ":" -f 2
  name_vps=$(echo $a_site | cut -d ":" -f 2)
  echo -e "========================   ${Red_font_prefix}${name_vps}${Font_color_suffix}   ========================"

else     
out=$(ping $a_site -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  
fi

done






##########################

<<'MULTILINE-COMMENT'





#!/usr/local/bin/bash
read -p "ping n (default 3)=" PING_N_input
if   [[ -z "$PING_N_input" ]]; then
        n=3
else
n=${PING_N_input}
fi






out=$(ping g1.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  

 

 

out=$(ping az.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  


out=$(ping az2.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  






out=$(ping m3.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  

out=$(ping m3ml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  


out=$(ping m2.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  

out=$(ping m2ml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  

out=$(ping m1ml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )

out=$(ping m1ml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  


out=$(ping m1.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site 




#
#out=$(ping cml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site  
#
#out=$(ping c.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site  
#
#
#out=$(ping c2.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site  
#
#
#
#out=$(ping as.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site  
#
#
#out=$(ping as2.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site  
#
#out=$(ping asml.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
#site=$(echo $out | cut -d ' ' -f 2)
#loss=$(echo $out | cut -d ' ' -f 12)
#ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
#echo $loss $ping $site 

MULTILINE-COMMENT
