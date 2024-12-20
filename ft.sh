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
#if lsof -i :$port > /dev/null; then
#    echo "Error: Port $port is already in use."
#    exit 1
#fi

# Check if netstat is available on the system
if command -v netstat &> /dev/null; then
    # Check using netstat for listening sockets and associated programs
    if netstat -tulpn 2>/dev/null | grep -q ":$port\b"; then
        echo "Error: Port $port is already in use by the following listening service(s):"
        netstat -tulpn 2>/dev/null | grep ":$port\b" | awk '{print $7}' | sort -u
        exit 1
    fi
else
    echo "Error: netstat is not available on the system."
    exit 2
fi

#echo "Port $port is free to use."



# Continue with the rest of your script if the port is not in use
echo -en "Port ${RED}$port is free available.${PLAIN}"

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
cd  $folder_name/
# Download the docker-compose file from the repository
curl -s https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml -o docker-compose.yml

wget -q  -4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_info.txt
wget -q -4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/update_bot_name.sh
wget -q -4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/show_results.sh

#sed -i 's/127.0.0.1:8080:8080/8080:8080/' docker-compose.yml

# Replace the port in the docker-compose.yml file
sed -i "s/127.0.0.1:8080:8080/${port}:8080/" docker-compose.yml
#sed -i "s/container_name: freqtrade/container_name: ft_${folder_name}_${port}/" docker-compose.yml
### sed -i "s/container_name: freqtrade/container_name: ft_${folder_name}/" docker-compose.yml

if [[ "${folder_name}" =~ ^[a-zA-Z] ]]; then
  sed -i "s/container_name: freqtrade/container_name: ${folder_name}/" docker-compose.yml
else
  sed -i "s/container_name: freqtrade/container_name: ft_${folder_name}/" docker-compose.yml
fi





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
#echo -en "Enter your choice ${RED}(freqtrade:1,   generate:2,   freqai:3),default 3:${PLAIN} "
echo -en "Enter your choice ${RED}(freqtrade:1,   generate:2,   freqai:3),default 3:${PLAIN} "
read  choice

###read -p "Enter your spot/futures (default for spot, 1 for futures): " choice_spot_futures
echo -en  "Enter your spot/futures (${RED}default for spot, 1 for futures${PLAIN}): " 
read choice_spot_futures





# Default to 1 if no input is given
if [ -z "$choice" ]; then
    choice=3
fi

case $choice in
3)
sed -i "s/SampleStrategy//"  docker-compose.yml
echo '      --freqaimodel  ' >> docker-compose.yml
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/download_freqaimodels.sh  )

        # Method 3: Download the AI configuration file and update the docker image
        mkdir -p user_data
      # wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/config_freqai.json
        wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/config.json_AI_template.json
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
      # wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_config.json
   ##   wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_config_use.json
        wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/config.json_AI_template.json
	# set freqai to false
	jq '.freqai.enabled = false' user_data/config.json > temp.json && mv temp.json user_data/config.json
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/download_freqaimodels.sh  )
        if [ $? -eq 0 ]; then
            echo "Configuration file downloaded successfully."
        else
            echo "Failed to download the configuration file."
        fi
        ;;

    2)
        # Method 2: Create a new configuration with docker-compose
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/download_freqaimodels.sh  )
        docker-compose run --rm freqtrade new-config --config user_data/config.json
        ;;

    *)
#     # echo "Invalid choice. Defaulting to method 1."
        echo "wrong input"
	exit 1
#       echo "Defaulting to method 1."
#       mkdir -p user_data
#       wget -4O "user_data/config.json" https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/ft_config.json
#       if [ $? -eq 0 ]; then
#           echo "Configuration file downloaded successfully."
#       else
#           echo "Failed to download the configuration file."
#       fi
        ;;
esac







# Pull the freqtrade image
docker-compose pull
# Create user directory structure
docker-compose run --rm freqtrade create-userdir --userdir user_data

#sed -i "s/SampleStrategy//"  docker-compose.yml

#if [ "$choice" -eq 3 ]; then
#  echo '      --freqaimodel  ' >> docker-compose.yml
#  bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/download_freqaimodels.sh  )
#fi
#
####### for download
wget -4 -O  config.json_AI_template.json  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/config.json_AI_template.json



wget -4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/append_to_head.txt
touch del.txt
cat append_to_head.txt docker-compose.yml > del.txt
mv del.txt docker-compose.yml
###rm append_to_head.txt 
#######


if [ -z "$choice_spot_futures" ]; then
  sed -i 's/"trading_mode": "futures"/"trading_mode": "spot"/' user_data/config.json
  sed -i '/"margin_mode": "isolated"/d' user_data/config.json
  sed -i 's/:USDT//g' user_data/config.json
  echo "user_data/config.json has been updated for spot trading"
  #update spot pairs
  bash  <(curl --ipv4  -Lk https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/spot_copy_active_pairs.sh  )
elif [ "$choice_spot_futures" = "1" ]; then
	# futures
  echo "futures : No changes made to user_data/config.json"
else
  echo "Invalid choice_spot_futures. No changes made to user_data/config.json"
fi




chmod -R 777  *

sudo chown -R 1000:1000  ../$folder_name
#cd  ../$folder_name
docker-compose down 
echo -en "       ${RED}${folder_name}${PLAIN} on ${RED}${port}${PLAIN} created "


