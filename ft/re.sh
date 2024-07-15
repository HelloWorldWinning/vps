#!/bin/bash

previous_output=""

while true; do
    current_output=$(fd .job | xargs exa -lh --sort newest)
    
    if [ "$current_output" != "$previous_output" ]; then
        clear  # Clear the screen
        echo "$current_output"
        previous_output="$current_output"
    fi
    
    sleep 1
done
