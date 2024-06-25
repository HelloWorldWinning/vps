#!/usr/bin/bash
###########
####!/bin/bash
# Extract the --freqaimodel value using awk
#model_name=$(awk '/--freqaimodel/ { print $NF }' docker-compose.yml)
# Get the current time tag in the desired format
time_tag=$(date "+%Y-%m-%d_%H-%M-%S")
 
model_name=$(awk '!/^[[:space:]]*#/ && /--freqaimodel/ { print $NF }' docker-compose.yml)
strategy=$(awk '!/^[[:space:]]*#/ && /--strategy/ { print $NF }' docker-compose.yml)
# Check if both model_name and strategy exist
if [[ -n $model_name && -n $strategy ]]; then
    # Combine model_name and strategy
    bot_name="${strategy} === ${model_name}"
    # Create identifier with model_name, strategy, and time_tag
   #identifier="${strategy}___${model_name}___${time_tag}"
    identifier="${strategy}___${model_name}"
    # Use jq to update bot_name and identifier in config.json, ensuring atomic update
    jq --arg bot_name "$bot_name" --arg identifier "$identifier" \
       '.bot_name = $bot_name | .freqai.identifier = $identifier' \
       user_data/config.json > user_data/tmp.config.json && \
    mv user_data/tmp.config.json user_data/config.json
    echo -e "\n    \033[31m$identifier\033[0m  Identifier updated in config.json"
    echo -e "\n    \033[31m$bot_name\033[0m     is updated to bot_name in config.json\n"
# Check if only strategy exists
elif [[ -n $strategy ]]; then
    # Use jq to update bot_name in config.json, ensuring atomic update
    jq --arg strategy "$strategy" \
       '.bot_name = $strategy' \
       user_data/config.json > user_data/tmp.config.json && \
    mv user_data/tmp.config.json user_data/config.json
    echo -e "\n    \033[31m$strategy\033[0m     is updated to bot_name in config.json\n"
else
    echo "Failed to extract model name or strategy from docker-compose.yml"
fi
# Ensure correct file ownership
chown -R 1000:1000 *
