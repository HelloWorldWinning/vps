#!/bin/bash

# Extract the --freqaimodel value using awk
model_name=$(awk '/--freqaimodel/ { print $NF }' docker-compose.yml)

# Check if the model_name variable is not empty
if [[ -n $model_name ]]; then
    # Use jq to update bot_name in config.json, ensuring atomic update
    jq --arg model_name "$model_name" '.bot_name = $model_name' user_data/config.json > user_data/tmp.config.json && mv user_data/tmp.config.json user_data/config.json
    echo "bot_name updated to $model_name in config.json"
else
    echo "Failed to extract model name from docker-compose.yml"
fi


chown -R 1000:1000 *
