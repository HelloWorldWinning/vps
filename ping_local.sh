#!/usr/local/bin/bash
n=5

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



out=$(ping az3.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  



out=$(ping az2.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  


out=$(ping gcp.wardao.xyz -c ${n} | grep -E 'loss$|^---|^round')
site=$(echo $out | cut -d ' ' -f 2)
loss=$(echo $out | cut -d ' ' -f 12)
ping=$(echo $out | cut -d ' ' -f 18  | sed "s/\.[0-9][0-9][0-9]//g" )
echo $loss $ping $site  
