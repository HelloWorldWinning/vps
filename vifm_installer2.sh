#!/bin/bash

# Install vifm
apt install -y vifm

# Setup variables
default_scheme=gruvbox
vifm_colors_dir=~/.config/vifm/colors
mkdir -p "$vifm_colors_dir"

# Clone the repository
git clone https://github.com/vifm/vifm-colors.git /tmp/vifm-colors
cp /tmp/vifm-colors/*.vifm "$vifm_colors_dir/"
rm -rf /tmp/vifm-colors

# Add alias if not present
if ! grep -q "alias vv='vifm'" ~/.bashrc; then
    echo "alias vv='vifm'" >> ~/.bashrc
fi

# Create vifmrc with color schemes
{
    echo "set relativenumber"
    echo "set number"
    echo "colorscheme $default_scheme"
    for theme in "$vifm_colors_dir"/*.vifm; do
        theme_name=$(basename "$theme" .vifm)
        if [ "$theme_name" != "$default_scheme" ]; then
            echo "\"colorscheme $theme_name"
        fi
    done
} > ~/.config/vifm/vifmrc

source ~/.bashrc

echo "Current vifmrc content:"
cat ~/.config/vifm/vifmrc
