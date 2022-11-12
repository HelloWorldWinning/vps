today_all=$(curl -s --max-time 10 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false" | tail -3 | head -n 1 | awk '{print $5,$7}')
#echo $today_all

today_hit=$(echo "${today_all}"|cut -d" " -f1)
all_hit=$(echo "${today_all}"|cut -d" " -f2)

echo $today_hit
echo $all_hit
