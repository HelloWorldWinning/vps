#!/bin/bash
apt install  -y sudo

# Ask for folder name and set default to 'ft_userdata'
sudo  apt install docker-compose -y

read -p "Enter the folder name (default is ft_userdata): " folder_name
folder_name=${folder_name:-ft_userdata}

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
#sed -i 's/127.0.0.1:8080:8080/8080:8080/' docker-compose.yml
# Ask for user input for the port
read -p "Enter the port number you want to use: " port
# Replace the port in the docker-compose.yml file
sed -i "s/127.0.0.1:8080:8080/${port}:8080/" docker-compose.yml
sed -i "s/container_name: freqtrade/container_name: ${folder_name}_${port}/" docker-compose.yml


# Pull the freqtrade image
docker-compose pull

# Create user directory structure
docker-compose run --rm freqtrade create-userdir --userdir user_data

# Create configuration - Requires answering interactive questions
docker-compose run --rm freqtrade new-config --config user_data/config.json


# cd ..
sudo chown -R 1000:1000  ../$folder_name
# cd $folder_name/

echo " ${folder_name}_${port} created "

