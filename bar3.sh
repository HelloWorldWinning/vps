#!/bin/bash

# METHOD 2 - Pattern matching (8ms, but more reliable)
response=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754")
hit_data=$(echo "$response" | grep -o '[0-9]* / [0-9]*' | head -1)
today_hit=$(echo "$hit_data" | cut -d' ' -f1)
all_hit=$(echo "$hit_data" | cut -d' ' -f3)
echo ${today_hit:-0}
echo ${all_hit:-0}
