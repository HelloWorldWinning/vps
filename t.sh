RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'


#read -p  "Enter the ${RED}folder name${PLAIN}(default is ft_userdata): " 
echo -en  "Enter ${RED}folder name${PLAIN}(default is ft_userdata): " 
read folder_name
#read folder_name    

# \033[1;31m$1\033[0m
echo $folder_name
