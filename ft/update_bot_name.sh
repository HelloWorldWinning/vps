#!/usr/bin/bash
###########
####!/bin/bash

# Extract the --freqaimodel value using awk
model_name=$(awk '/--freqaimodel/ { print $NF }' docker-compose.yml)

# Get the current time tag in the desired format
time_tag=$(date "+%Y-%m-%d_%H-%M-%S")

# Check if the model_name variable is not empty
if [[ -n $model_name ]]; then
    # Use jq to update bot_name and identifier in config.json, ensuring atomic update
    jq --arg model_name "$model_name" --arg time_tag "$time_tag" \
       '.bot_name = $model_name | .freqai.identifier = $time_tag' \
       user_data/config.json > user_data/tmp.config.json && \
    mv user_data/tmp.config.json user_data/config.json
    echo -e "    \033[31m$model_name\033[0m     is updated to bot_name in config.json"
    echo -e "    \033[31m$time_tag\033[0m  Identifier updated to  in config.json"
else
    echo "Failed to extract model name from docker-compose.yml"
fi

# Ensure correct file ownership
chown -R 1000:1000 *

