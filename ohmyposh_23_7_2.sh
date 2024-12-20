#!/usr/bin/bash
apt install -y jq

#wget   --inet4-only  -O  ~/themes/update_prompt_date_DD_Day.sh   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/update_prompt_date_DD_Day.sh
#
curl -4SsL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/update_prompt_date_DD_Day.sh  >  ~/themes/update_prompt_date_DD_Day.sh 
chmod 777  ~/themes/update_prompt_date_DD_Day.sh

#curl -4SsL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/get_country_flag.sh  >  ~/themes/get_country_flag.sh
#chmod 777  ~/themes/get_country_flag.sh     

# Path to the update script
UPDATE_SCRIPT="$HOME/themes/update_prompt_date_DD_Day.sh"
# Set execute permissions for the update script
chmod +x "$UPDATE_SCRIPT"

# The crontab entry we want to add
#CRON_ENTRY="0 */1 * * * $UPDATE_SCRIPT"
CRON_ENTRY="*/1 * * * * $UPDATE_SCRIPT"

# Check if the crontab entry already exists
if crontab -l | grep -Fq "$UPDATE_SCRIPT"
then
    echo "Crontab entry already exists. No changes made."
else
    # If it doesn't exist, add it
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "Crontab entry added successfully."
fi

# Display the current crontab
echo "Current crontab entries:"
crontab -l




curl -4SsL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json    >   ~/themes/gmay3.omp.json
#wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json

bash  $HOME/themes/update_prompt_date_DD_Day.sh

curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash

wget   --inet4-only  -O  ~/themes/cpu_usage.sh  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/cpu_usage.sh 
# Define the cron job command
##cron_job_wea="0 */1 * * * curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash"
cron_job_wea="*/30 * * * * curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh | bash"

# Check if weather_temperature.sh is already in the crontab
if ! crontab -l | grep -q "weather_temperature.sh"; then
    # Add the cron job to the crontab
    (crontab -l ; echo "$cron_job_wea") | crontab -
    echo "Cron job appended successfully."
else
    echo "Cron job for weather temperature is already present in crontab. No action taken."
fi


install_dir=""
themes_dir=""
executable=""

error() {
    printf "\e[31m$1\e[0m\n"
    exit 1
}

info() {
    printf "$1\n"
}

warn() {
    printf "⚠️  \e[33m$1\e[0m\n"
}

help() {
    # Display Help
    echo "Install script for Oh My Posh"
    echo
    echo "Syntax: install.sh [-h|d|t]"
    echo "options:"
    echo "-h     Print this help."
    echo "-d     Specify the installation directory. Defaults to $HOME/bin, $HOME/.local/bin or the directory where oh-my-posh is installed."
    echo "-t     Specify the themes installation directory. Defaults to the oh-my-posh cache directory."
    echo
}

while getopts ":hd:t:" option; do
   case $option in
      h) # display Help
         help
         exit;;
      d) # Enter a name
         install_dir=${OPTARG};;
      t) # themes directory
         themes_dir=${OPTARG};;
     \?) # Invalid option
         echo "Invalid option command line option. Use -h for help."
         exit 1
   esac
done

SUPPORTED_TARGETS="linux-386 linux-amd64 linux-arm linux-arm64 darwin-amd64 darwin-arm64 freebsd-386 freebsd-amd64 freebsd-arm freebsd-arm64"

validate_dependency() {
    if ! command -v $1 >/dev/null; then
        error "$1 is required to install Oh My Posh. Please install $1 and try again.\n"
    fi
}

validate_dependencies() {
    validate_dependency curl
    validate_dependency unzip
    validate_dependency realpath
    validate_dependency dirname
}

set_install_directory() {
    if [ -n "$install_dir" ]; then
        # expand directory
        install_dir="${install_dir/#\~/$HOME}"
        return 0
    fi

    # check if we have oh-my-posh installed, if so, use the executable directory
    # to install into and follow symlinks
    if command -v oh-my-posh >/dev/null; then
        posh_dir=$(command -v oh-my-posh)
        real_dir=$(realpath $posh_dir)
        install_dir=$(dirname $real_dir)
        info "Oh My Posh is already installed, updating existing installation in:"
        info "  ${install_dir}"
        return 0
    fi

    # check if $HOME/bin exists and is writable
    if [ -d "$HOME/bin" ] && [ -w "$HOME/bin" ]; then
        install_dir="$HOME/bin"
        return 0
    fi

    # check if $HOME/.local/bin exists and is writable
    if ([ -d "$HOME/.local/bin" ] && [ -w "$HOME/.local/bin" ]) || mkdir -p "$HOME/.local/bin"; then
        install_dir="$HOME/.local/bin"
        return 0
    fi

    error "Cannot determine installation directory. Please specify a directory and try again: \ncurl -s https://ohmyposh.dev/install.sh | bash -s -- -d {directory}"
}

validate_install_directory() {
    #check if installation dir exists
    if [ ! -d "$install_dir" ]; then
        error "Directory ${install_dir} does not exist, set a different directory and try again."
    fi

    # Check if regular user has write permission
    if [ ! -w "$install_dir" ]; then
        error "Cannot write to ${install_dir}. Please check write permissions or set a different directory and try again: \ncurl -s https://ohmyposh.dev/install.sh | bash -s -- -d {directory}"
    fi

    # check if the directory is in the PATH
    good=$(
        IFS=:
        for path in $PATH; do
        if [ "${path%/}" = "${install_dir}" ]; then
            printf 1
            break
        fi
        done
    )

    if [ "${good}" != "1" ]; then
        warn "Installation directory ${install_dir} is not in your \$PATH, add it using \nexport PATH=\$PATH:${install_dir}"
    fi
}

validate_themes_directory() {

    # Validate if the themes directory exists
    if ! mkdir -p "$themes_dir" > /dev/null 2>&1; then
        error "Cannot write to ${themes_dir}. Please check write permissions or set a different directory and try again: \ncurl -s https://ohmyposh.dev/install.sh | bash -s -- -t {directory}"
    fi

    #check user write permission
    if [ ! -w "$themes_dir" ]; then
        error "Cannot write to ${themes_dir}. Please check write permissions or set a different directory and try again: \ncurl -s https://ohmyposh.dev/install.sh | bash -s -- -t {directory}"
    fi
}

install_themes() {
    if [ -n "$themes_dir" ]; then
        # expand directory
        themes_dir="${themes_dir/#\~/$HOME}"
    fi

    cache_dir=$($executable cache path)

    # validate if the user set the path to the themes directory
    if [ -z "$themes_dir" ]; then
        themes_dir="${cache_dir}/themes"
    fi

    validate_themes_directory

    info "🎨 Installing oh-my-posh themes in ${themes_dir}\n"

    zip_file="${cache_dir}/themes.zip"

    url="https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v23.7.2/themes.zip"

    http_response=$(curl -s -f -L $url -o $zip_file -w "%{http_code}")

    if [ $http_response = "200" ] && [ -f $zip_file ]; then
        unzip -o -q $zip_file -d $themes_dir
        # make sure the files are readable and writable for all users
        chmod a+rwX ${themes_dir}/*.omp.*
        rm $zip_file
    else
        warn "Unable to download themes at ${url}\nPlease validate your curl, connection and/or proxy settings"
    fi
}

install() {
    arch=$(detect_arch)
    platform=$(detect_platform)
    target="${platform}-${arch}"

    good=$(
        IFS=" "
        for t in $SUPPORTED_TARGETS; do
        if [ "${t}" = "${target}" ]; then
            printf 1
            break
        fi
        done
    )

    if [ "${good}" != "1" ]; then
        error "${arch} builds for ${platform} are not available for Oh My Posh"
    fi

    info "\nℹ️  Installing oh-my-posh for ${target} in ${install_dir}"

    executable=${install_dir}/oh-my-posh
    url=https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v23.7.2/posh-${target}

    info "⬇️  Downloading oh-my-posh from ${url}"

    http_response=$(curl -s -f -L $url -o $executable -w "%{http_code}")

    if [ $http_response != "200" ] || [ ! -f $executable ]; then
        error "Unable to download executable at ${url}\nPlease validate your curl, connection and/or proxy settings"
    fi

    chmod +x $executable

    install_themes

    info "🚀 Installation complete.\n\nYou can follow the instructions at https://ohmyposh.dev/docs/installation/prompt"
    info "to setup your shell to use oh-my-posh."
    if [ $http_response = "200" ]; then
        info "\nIf you want to use a built-in theme, you can find them in the ${themes_dir} directory:"
        info "  oh-my-posh init {shell} --config ${themes_dir}/{theme}.omp.json\n"
    fi
}

detect_arch() {
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

  case "${arch}" in
    x86_64) arch="amd64" ;;
    armv*) arch="arm" ;;
    arm64) arch="arm64" ;;
    aarch64) arch="arm64" ;;
    i686) arch="386" ;;
  esac

  if [ "${arch}" = "arm64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
    arch=arm
  fi

  printf '%s' "${arch}"
}


detect_platform() {
  platform="$(uname -s | awk '{print tolower($0)}')"

  case "${platform}" in
    linux) platform="linux" ;;
    darwin) platform="darwin" ;;
  esac

  printf '%s' "${platform}"
}

validate_dependencies
set_install_directory
validate_install_directory
install

bash    ~/themes/update_prompt_date_DD_Day.sh
