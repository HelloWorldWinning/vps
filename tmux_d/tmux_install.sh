#!/bin/bash

# Install tmux if not already installed
sudo apt install -y tmux

# Clone the oh-my-tmux repository
#git clone https://github.com/gpakosz/.tmux.git /data/.oh-my-tmux_d
git clone https://github.com/gpakosz/.tmux.git  ~/.oh-my-tmux_d

# Create the tmux configuration directory
mkdir -p ~/.config/tmux

# Create a symbolic link for the tmux configuration file
#sudo ln -sf "$PWD/oh-my-tmux_d/.tmux.conf" ~/.config/tmux/tmux.conf
#sudo ln -sf  /data/.oh-my-tmux_d/.tmux.conf ~/.config/tmux/tmux.conf
sudo ln -sf   ~/.oh-my-tmux_d/.tmux.conf ~/.config/tmux/tmux.conf

# Copy the local tmux configuration file
#cp /data/.oh-my-tmux_d/.tmux.conf.local ~/.config/tmux/tmux.conf.local

wget -4 -O ~/.config/tmux/tmux.conf.local  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/tmux.conf.local

wget -4 -O ~/.config/tmux/python_version.sh   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/python_version.sh

wget -4 -O ~/.config/tmux/get_country_flag.sh     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/get_country_flag.sh 
chmod 777 ~/.config/tmux/get_country_flag.sh 

#curl -4SsL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/get_country_flag.sh  >  ~/themes/get_country_flag.sh
#chmod 777  ~/themes/get_country_flag.sh     



#######echo 'tmux source-file ~/.config/tmux/tmux.conf' >> ~/.bashrc

if ! grep -q 'tmux source-file ~/.config/tmux/tmux.conf' ~/.bashrc; then
  echo 'tmux source-file ~/.config/tmux/tmux.conf' >> ~/.bashrc
  echo "The line 'tmux source-file ~/.config/tmux/tmux.conf' has been appended to ~/.bashrc"
else
  echo "The line 'tmux source-file ~/.config/tmux/tmux.conf' already exists in ~/.bashrc"
fi


# Start a new tmux session

####curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/bashrc_alias.txt >> ~/.bashrc

if ! grep -q "bashrc_alias_txt_unique_id_check_info" ~/.bashrc; then
  curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/bashrc_alias.txt >> ~/.bashrc
fi


# Reload the tmux configuration
tmux source-file ~/.config/tmux/tmux.conf
tmux new-session
