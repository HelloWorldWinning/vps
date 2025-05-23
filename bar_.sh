today_all=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754" | tail -3 | head -n 1 | awk '{print $5,$7}')
#echo $today_all

today_hit=$(echo "${today_all}"|cut -d" " -f1)
all_hit=$(echo "${today_all}"|cut -d" " -f2)


echo $today_hit
echo $all_hit
