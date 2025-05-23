#!/bin/bash

# Get the API response
response=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754")

# Method 1: Try to extract from SVG text elements
start_time=$(date +%s%N)
today_hit=$(echo "$response" | grep -o 'textLength="[0-9]*">[0-9]*</text>' | tail -1 | sed 's/textLength="[0-9]*">\([0-9]*\)<\/text>/\1/')
all_hit=$(echo "$response" | grep -o 'textLength="[0-9]*">[0-9]* / [0-9]*</text>' | sed 's/textLength="[0-9]*">\([0-9]*\) \/ \([0-9]*\)<\/text>/\2/')
end_time=$(date +%s%N)
method1_time=$((($end_time - $start_time) / 1000000))
echo "Method 1 time: ${method1_time}ms"

# Method 2: If Method 1 fails, try extracting from the "4 / 4" pattern
if [[ -z "$today_hit" || -z "$all_hit" ]]; then
    start_time=$(date +%s%N)
    hit_data=$(echo "$response" | grep -o '[0-9]* / [0-9]*' | head -1)
    if [[ -n "$hit_data" ]]; then
        today_hit=$(echo "$hit_data" | cut -d' ' -f1)
        all_hit=$(echo "$hit_data" | cut -d' ' -f3)
    fi
    end_time=$(date +%s%N)
    method2_time=$((($end_time - $start_time) / 1000000))
    echo "Method 2 time: ${method2_time}ms"
fi

# Method 3: Alternative parsing if the above methods fail
if [[ -z "$today_hit" || -z "$all_hit" ]]; then
    start_time=$(date +%s%N)
    numbers=$(echo "$response" | grep -o '[0-9]\+' | tail -2)
    if [[ $(echo "$numbers" | wc -l) -eq 2 ]]; then
        today_hit=$(echo "$numbers" | head -1)
        all_hit=$(echo "$numbers" | tail -1)
    fi
    end_time=$(date +%s%N)
    method3_time=$((($end_time - $start_time) / 1000000))
    echo "Method 3 time: ${method3_time}ms"
fi

# Fallback values if extraction fails
today_hit=${today_hit:-0}
all_hit=${all_hit:-0}

echo "$today_hit"
echo "$all_hit"

# Optional: Display in the format you want
echo "Hit count: $today_hit/$all_hit"

echo ""
echo "=== SPEED-OPTIMIZED VERSION ==="
echo "Copy the fastest method below into a new script:"
echo ""

# Show the fastest single-method versions
cat << 'EOF'
# FAST METHOD 1 (SVG parsing):
response=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754")
today_hit=$(echo "$response" | grep -o 'textLength="[0-9]*">[0-9]*</text>' | tail -1 | sed 's/textLength="[0-9]*">\([0-9]*\)<\/text>/\1/')
all_hit=$(echo "$response" | grep -o 'textLength="[0-9]*">[0-9]* / [0-9]*</text>' | sed 's/textLength="[0-9]*">\([0-9]*\) \/ \([0-9]*\)<\/text>/\2/')
echo ${today_hit:-0}; echo ${all_hit:-0}

# FAST METHOD 2 (Pattern matching):
response=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754")
hit_data=$(echo "$response" | grep -o '[0-9]* / [0-9]*' | head -1)
today_hit=$(echo "$hit_data" | cut -d' ' -f1)
all_hit=$(echo "$hit_data" | cut -d' ' -f3)
echo ${today_hit:-0}; echo ${all_hit:-0}

# FAST METHOD 3 (Number extraction):
response=$(curl -s --max-time 10 "https://hitscounter.dev/api/hit?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps%2Fmain%2Fgoodv3.sh&label=try&icon=alarm&color=%23198754")
numbers=$(echo "$response" | grep -o '[0-9]\+' | tail -2)
echo "$numbers" | head -1
echo "$numbers" | tail -1
EOF
