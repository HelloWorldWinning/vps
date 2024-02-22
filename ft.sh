#!/bin/bash
RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

apt install  -y sudo lsof

# Ask for folder name and set default to 'ft_userdata'
sudo  apt install docker-compose -y

#read -p "Enter the folder name (default is ft_userdata): " folder_name
clear
echo -en "Enter ${RED}folder name ${PLAIN}(default is ft_userdata): "
read folder_name
folder_name=${folder_name:-ft_userdata}

# Ask for user input for the port
echo -en "Enter the ${RED}port ${PLAIN}number you want to use: " 
read port

# Check if the port is already in use
if lsof -i :$port > /dev/null; then
    echo "Error: Port $port is already in use."
    exit 1
fi

# Continue with the rest of your script if the port is not in use
echo -en "Port ${RED}$port is available.${PLAIN}"

folder_name="${folder_name}_${port}"

# Check if folder exists
if [ -d "$folder_name" ]; then
    echo "Error: Folder already exists."
    exit 1
else
    mkdir "$folder_name"
    echo "Folder $folder_name created."
fi

#mkdir ft_userdata
#cd ft_userdata/
cd  $folder_name/
# Download the docker-compose file from the repository
curl https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml -o docker-compose.yml

wget -4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_info.txt

#sed -i 's/127.0.0.1:8080:8080/8080:8080/' docker-compose.yml

# Replace the port in the docker-compose.yml file
sed -i "s/127.0.0.1:8080:8080/${port}:8080/" docker-compose.yml
#sed -i "s/container_name: freqtrade/container_name: ft_${folder_name}_${port}/" docker-compose.yml
sed -i "s/container_name: freqtrade/container_name: ft_${folder_name}/" docker-compose.yml

# Create configuration - Requires answering interactive questions
#docker-compose run --rm freqtrade new-config --config user_data/config.json


#!/bin/bash

# Prompt the user to choose a method, with a default of 1
echo "Select a method to execute (default is 1):"
echo "1. Download configuration file with wget"
echo "2. Create a new configuration with docker-compose"
echo "3. Download AI configuration file with wget"
#read -p "Enter your choice (1 or 2), press Enter for default: " choice
#read -p "Enter your choice (1 or 2),default 1: " choice
#read -p "Enter your choice {RED}(1,generate:2,AI:3),default 1: " choice
echo -en "Enter your choice ${RED}(1,generate:2,AI:3),default 3:${PLAIN} "
read  choice

# Default to 1 if no input is given
if [ -z "$choice" ]; then
    choice=3
fi

case $choice in
3)
        # Method 3: Download the AI configuration file and update the docker image
        mkdir -p user_data
        wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/config_freqai.json
        if [ $? -eq 0 ]; then
            echo "AI configuration file downloaded successfully."
            # Now comment out the existing image line and add the new image line
            awk '/image: freqtradeorg\/freqtrade:stable/ {
                print "    image: freqtradeorg/freqtrade:develop_freqai" # Adjust indentation as needed
                print "#   image: freqtradeorg/freqtrade:develop_freqaitorch" 
                print "#   image: freqtradeorg/freqtrade:develop_freqairl" 
                print "    #"$0 # Ensure this matches the file s indentation style
                next
            }
            { print }' docker-compose.yml > temp.yml && mv temp.yml docker-compose.yml
            echo "Docker image updated to AI version."
        else
            echo "Failed to download the AI configuration file."
        fi
        ;;
    1)
        # Method 1: Download the configuration file
	mkdir -p user_data
        wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_config.json
        if [ $? -eq 0 ]; then
            echo "Configuration file downloaded successfully."
        else
            echo "Failed to download the configuration file."
        fi
        ;;

    2)
        # Method 2: Create a new configuration with docker-compose
        docker-compose run --rm freqtrade new-config --config user_data/config.json
        ;;

    *)
      # echo "Invalid choice. Defaulting to method 1."
        echo "Defaulting to method 1."
	mkdir -p user_data
        wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_config.json
        if [ $? -eq 0 ]; then
            echo "Configuration file downloaded successfully."
        else
            echo "Failed to download the configuration file."
        fi
        ;;
esac




# Pull the freqtrade image
docker-compose pull

# Create user directory structure
docker-compose run --rm freqtrade create-userdir --userdir user_data


# cd ..
sudo chown -R 1000:1000  ../$folder_name
#cd $folder_name/

sed -i "s/SampleStrategy//"  docker-compose.yml
echo '      --freqaimodel  ' >> docker-compose.yml

echo -en "       ${RED}${folder_name}${PLAIN} on ${RED}${port}${PLAIN} created "
