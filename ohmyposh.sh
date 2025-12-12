#!/bin/bash
curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash
#wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json
mkdir -p /root/themes
wget --inet4-only -O /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json_for_new_oh_my_posh

# Define the cron job command
##cron_job_wea="0 */1 * * * curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash"
cron_job_wea="*/30 * * * * curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash"

# Check if weather_temperature.sh is already in the crontab
if ! crontab -l | grep -q "weather_temperature.sh"; then
	# Add the cron job to the crontab
	(
		crontab -l
		echo "$cron_job_wea"
	) | crontab -
	echo "Cron job appended successfully."
else
	echo "Cron job for weather temperature is already present in crontab. No action taken."
fi

apt install -y unzip jq wget
clear
curl -4s https://ohmyposh.dev/install.sh | bash -s
####curl -4s  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh_23_7_2.sh  |   bash -s
mkdir -p ~/themes/
wget --inet4-only -O ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json

wget --inet4-only -O ~/themes/hostname_length_adjuster.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/hostname_length_adjuster.sh

wget --inet4-only -O ~/themes/cpu_usage.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/cpu_usage.sh

########## bash  ~/themes/hostname_length_adjuster.sh

#cat >>~/.bashrc<<EOF
#export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
##bash  ~/themes/hostname_length_adjuster.sh
#eval "\$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
#EOF

####
####if ! grep -q "export country_code=" ~/.bashrc; then
####
####    cat >> ~/.bashrc << 'END'
####export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
#####bash  ~/themes/hostname_length_adjuster.sh
####eval "$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
####END
####
####fi
####
####

wget --inet4-only -O ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json

country_code_weather_alias='
country_code_file=~/.country_code

if [ -f "$country_code_file" ]; then
  export country_code=$(cat "$country_code_file")
else 
  export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
  echo "$country_code" > "$country_code_file"
fi

alias wea="source <(curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh)"
'

if ! grep -q -F "$country_code_weather_alias" ~/.bashrc; then
	echo "$country_code_weather_alias" >>~/.bashrc
	echo "Country code weather alias appended to ~/.bashrc"
else
	echo "Country code weather alias already exists in ~/.bashrc. No changes made."
fi

oh-my-posh --version

# Append set_poshcontext into /root/.bashrc only if the marker id isn't already present
if ! grep -qF 'id=gmay3_omp_json_for_new_oh_my_posh' /root/.bashrc 2>/dev/null; then
	cat >>~/.bashrc <<'EOF'

# ============================================================================
# Add this function to your ~/.bashrc or ~/.zshrc BEFORE the oh-my-posh init line
# ============================================================================

function set_poshcontext() {
    # id=gmay3_omp_json_for_new_oh_my_posh
    # 1) Directory + file count + flag (replaces dirname/basename/ls/flag logic)
    local pwd_path parent base count flag parent_dir

    pwd_path="$(pwd)"
    if [ "$pwd_path" = "/" ]; then
        parent="<i>/</i>"
        base=""
    else
        parent_dir="$(dirname "$pwd_path")"
        if [ "$parent_dir" = "/" ]; then
            parent="<i>/</i>"
        else
            parent="<i>${parent_dir}/</i>"
        fi
        base="<b>$(basename "$pwd_path")</b>"
    fi

    count="$(ls -1A 2>/dev/null | wc -l | tr -d ' ')"

    # ---- FIXED FLAG SECTION ----
    if [ -n "$country_code" ]; then
        # first and second letters as ASCII codes
        local first_char second_char c1 c2 u1 u2

        first_char="${country_code%${country_code#?}}" # first char
        second_char="${country_code#?}"                # second char

        c1=$(printf '%d' "'$first_char")
        c2=$(printf '%d' "'$second_char")

        # convert to regional indicator symbols (must be 8-digit hex!)
        u1=$(printf '%08X' $((c1 + 127462 - 65)))
        u2=$(printf '%08X' $((c2 + 127462 - 65)))

        # printf interprets \Uhhhhhhhh → actual emoji 🇳🇱 etc.
        flag="$(printf "\\U$u1\\U$u2") "
    else
        flag=" Unknown "
    fi
    # ---- END FLAG SECTION ----

    export POSH_DIR_INFO="       ${parent}${base}<b>      ${count}      </b> <#988999>${flag}"

    # 2) Python + conda env (same as before)
    local python_version conda_env
    python_version="$(command -v python >/dev/null 2>&1 && python --version 2>&1 | awk '{print $2}' || echo '')"
    conda_env="${CONDA_DEFAULT_ENV}"

    if [ -z "$conda_env" ] && [ -z "$python_version" ]; then
        export POSH_PYTHON_INFO=""
    else
        export POSH_PYTHON_INFO="${conda_env} ${python_version}"
    fi

    # 3) Weather (same as before)
    if [ -f "$HOME/.weather_temperature" ]; then
        export POSH_WEATHER="$(cat "$HOME/.weather_temperature")"
    else
        export POSH_WEATHER=""
    fi
}


EOF
fi
