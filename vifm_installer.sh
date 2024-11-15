#!/bin/bash


apt install -y vifm

default_scheme=gruvbox

mkdir -p ~/.config/vifm/colors

THEMES=("afterglow" "ansa" "darkdesert" "crown_24bit" "desert" "dracula" "dwmlight" "fargo" "gruvbox" "lucius" "iceberg" "matrix" "mc-like" "monochrome" "molokai" "near-default" "nord" "onedark" "palenight" "paper" "papercolor-dark" "papercolor-light" "ph" "retrobox" "reicheltd-light" "sandy" "semidarkdesert" "solarized-dark" "solarized-light" "snowwhite" "truedark" "zenburn" "zenburn_1")

BASE_URL="https://raw.githubusercontent.com/vifm/vifm-colors/master"
for theme in "${THEMES[@]}"; do
   curl -o ~/.config/vifm/colors/${theme}.vifm $BASE_URL/${theme}.vifm
done

if ! grep -q "alias vv='vifm'" ~/.bashrc; then
   echo "alias vv='vifm'" >> ~/.bashrc
fi

{
   echo "colorscheme $default_scheme"
   for theme in "${THEMES[@]}"; do
       if [ "$theme" != "$default_scheme" ]; then
           echo "\"colorscheme $theme"
       fi
   done
} > ~/.config/vifm/vifmrc

source ~/.bashrc

echo "Current vifmrc content:"
cat ~/.config/vifm/vifmrc
