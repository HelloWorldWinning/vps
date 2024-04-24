#!/bin/bash

# Install tmux if not already installed
sudo apt install -y tmux

# Clone the oh-my-tmux repository
git clone https://github.com/gpakosz/.tmux.git /data/.oh-my-tmux_d

# Create the tmux configuration directory
mkdir -p ~/.config/tmux

# Create a symbolic link for the tmux configuration file
#sudo ln -sf "$PWD/oh-my-tmux_d/.tmux.conf" ~/.config/tmux/tmux.conf
sudo ln -sf  /data/.oh-my-tmux_d/.tmux.conf ~/.config/tmux/tmux.conf

# Copy the local tmux configuration file
#cp /data/.oh-my-tmux_d/.tmux.conf.local ~/.config/tmux/tmux.conf.local

wget -4 -O ~/.config/tmux/tmux.conf.local  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/tmux.conf.local

wget -4 -O ~/.config/tmux/python_version.sh   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/python_version.sh

echo 'tmux source-file ~/.config/tmux/tmux.conf' >> ~/.bashrc

# Reload the tmux configuration
tmux source-file ~/.config/tmux/tmux.conf

# Start a new tmux session

curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/bashrc_alias.txt >> ~/.bashrc
tmux new-session
