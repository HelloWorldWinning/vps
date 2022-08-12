#!/usr/bin/env bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

lite_location='
eastasia\n
southeastasia\n
japaneast\n
japanwest\n
ukwest\n
uksouth\n
westus2\n
westus\n'

all_location='\n
westus\n
centralus\n
northcentralus\n
westcentralus\n
eastus\n
australiasoutheast\n
eastasia\n
westeurope\n
swedensouth\n
ukwest\n
northeurope\n
eastus2\n
southafricawest\n
southindia\n
southeastasia\n
japanwest\n
koreasouth\n
canadaeast\n
francesouth\n
germanynorth\n
norwaywest\n
switzerlandwest\n
uaecentral\n
southcentralus\n
centraluseuap\n
westeurope\n
southcentralus\n
eastus\n
jioindiacentral\n
eastus2euap\n
westus2\n
southafricanorth\n
australiacentral\n
australiacentral2\n
australiaeast\n
japaneast\n
jioindiawest\n
koreacentral\n
centralindia\n
southindia\n
canadacentral\n
francecentral\n
germanywestcentral\n
norwayeast\n
switzerlandnorth\n
uksouth\n
uaenorth\n
brazilsouth\n
'

echo -e $all_location
echo -e $lite_location

read -p 'create group name': group_name ;
read -p 'create vm name': vm_name ;

read  -p "$(echo -e "

1   eastasia
2   southeastasia
3   japaneast
4   japanwest
5   ukwest
6   uksouth
7   westus2
8   westus


others for input location

\r\n
")"  choose
        case $choose in

          1) location="eastasia" ;;
          2) location="southeastasia" ;;
          3) location="japaneast" ;;
          4) location="japanwest" ;;
          5) location="ukwest" ;;
          6) location="uksouth" ;;
          7) location="westus2" ;;
          8) location="westus" ;;

          *) read  -p  "user input = ": location ;;
        esac

echo $location

#read -p 'selec location default eastasia': location ;
#[[ -z "${location}" ]] && location=eastasia


_size="--size"

read  -p "$(echo -e "

0   auto
1   Standard_B1ms
2   Standard_B1s
3   Standard_B2ms
4   Standard_B2s
5   Standard_DS1_v26
6   Standard_DS2_v2
7   Standard_DS3_v2
8   Standard_DS4_v2
9  Standard_DS5_v2

others for input

\r\n
")"  choose
        case $choose in
          0)  _size=''  && size='' ;;
          1) size="Standard_B1ms" ;;
          2) size="Standard_B1s" ;;
          3) size="Standard_B2ms" ;;
          4) size="Standard_B2s" ;;
          5) size="Standard_DS1_v26" ;;
          6) size="Standard_DS2_v2" ;;
          7) size="Standard_DS3_v2" ;;
          8) size="Standard_DS4_v2" ;;
          9) size="Standard_DS5_v2" ;;

          *) read  -p  "user input = ": size ;;
        esac


#echo "$location" $location 
#echo "$group_name" ${group_name}
#echo "$vm_name" ${vm_name}
#echo ${_size} ${size}

#echo ${group_name} $location

az group create --name ${group_name} --location $location

az vm create --name  ${vm_name}   --location  $location   --resource-group ${group_name} ${_size} ${size} --accelerated-networking   true   --admin-username init --authentication-type ssh --image debian:debian-10:10:latest --public-ip-sku   standard   --zone   3 --os-disk-size-gb 64   --ssh-key-values  'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= '
