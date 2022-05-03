read -p 'input a grep  word to filter users<rdp default>': filter_input
if [[ -z "${filter_input}" ]] ; then
filter=rdp
else
filter=${filter_input}
fi

getent passwd | awk -F: '{ print $1}'| sort| grep  $filter

 
read -p 'input a existing user name to delete': rdp_username_input
if [[ -z "${rdp_username_input}" ]] ; then
 exit
else
rdp_username=$rdp_username_input
fi


sudo deluser ${rdp_username}
sudo deluser --remove-home ${rdp_username}
sudo deluser --remove-all-files ${rdp_username}
