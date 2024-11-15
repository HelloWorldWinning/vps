================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
https://hostloc.com/thread-1030881-1-1.html
https://netboot.xyz/docs/booting/grub/
 dd.sh 
# Install grub-imageboot
apt install grub-imageboot -y

# Download netboot.xyz ISO
yes | rm -r /boot/images 
mkdir -p  /boot/images
cd /boot/images
wget https://boot.netboot.xyz/ipxe/netboot.xyz.iso

# Update GRUB menu to include this ISO
update-grub2
reboot



================================================================
docker run -d --name dynalist --restart always oklove/dyna.v0.0.1.2.py:latest
================================================================
pip install -U huggingface_hub
================================================================
#### notebook
#3pip install mistune==0.8.4
#3pip install --upgrade nbconvert  jupyter  
#3pip install chardet


pip install chardet
conda update mistune
pip install --upgrade nbconvert  jupyter  


================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
================================================================
font
/*roboto mono   source code pro  Inconsolata-g noto sans mono  */
================================================================
# Create the missing nginx log directory
sudo mkdir -p /var/log/nginx

# Create the missing error.log file
sudo touch /var/log/nginx/error.log

# Set appropriate permissions for the error.log file
sudo chmod 644 /var/log/nginx/error.log
# Adjust user and group if your setup differs

sudo chown nginx:nginx /var/log/nginx/error.log 
# Test nginx configuration
nginx -t

# If the test is successful, restart nginx
# sudo systemctl restart nginx.service
================================================================




================================================================

@reboot sleep 4 ; bash -c "source ~/.bashrc;export PATH=/root/anaconda3/envs/Freqtrade/bin:$PATH; /root/anaconda3/envs/Freqtrade/bin/python  /etc/nginx/conf.d/1666.py "
================================================================


#!/bin/bash

# Find all .txt files and convert their encoding from GBK to UTF-8, overwriting the original files
find . -type f -name "*.txt" | while read -r file; do
    iconv -f GBK -t UTF-8 "$file" -o "$file"
done



================================================================

#!/bin/bash


# Find all .txt files and convert their encoding from GBK to UTF-8
find . -type f -name "*.txt" | while read -r file; do
    iconv -f GBK -t UTF-8 "$file" > "${file%.txt}-utf8.txt"
done

================================================================

iptables -t nat --line-numbers -L


# Redirect incoming traffic on port 80 to your VPS's IP address:port
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 5.6.7.8:80

# Masquerade (modify source address) for outgoing traffic
sudo iptables -t nat -A POSTROUTING -j MASQUERADE


sudo iptables -t nat -D <chain_name> <rule_number>



================================================================
"outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "uk.today",
            "port": 80,
            "users": [
              {
                "id": "12345678-1234-1234-1234-123456789012",
                "security": "aes-128-gcm"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/"
        }
      }
    },
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]





================================================================

 cat t7.yaml
log:
  loglevel: info
inbounds:
  - port: 7777
    protocol: trojan
    settings:
      clients:
        - password: '1'
    streamSettings:
      network: ws
      security: none
      wsSettings:
        path: /
outbounds:
  - protocol: freedom
================================================================
# 大盘鸡
# Install NFS Server
sudo apt update
sudo apt install nfs-kernel-server

# Prompt for the IP address of the client VPS that will access this server
read -p "Enter the IP address of the Client VPS (VPS B) to share resources with: " client_vps_ip

# Configure NFS Exports
echo "/ ${client_vps_ip}(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports

# Export the NFS Shares and Restart the NFS Server
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# Adjust Firewall Settings (Optional, if applicable)
sudo ufw allow from ${client_vps_ip} to any port nfs
sudo ufw enable
sudo ufw status

----------------

# Install NFS Client
sudo apt update
sudo apt install nfs-common

# Prompt for the IP address of the NFS server VPS
read -p "Enter the IP address of the NFS Server VPS (VPS A) to mount its disk: " server_vps_ip

# Create Mount Point
sudo mkdir -p /mnt/vps_a_disk

# Add Mount Entry in /etc/fstab
echo "${server_vps_ip}:/ /mnt/vps_a_disk nfs defaults 0 0" | sudo tee -a /etc/fstab

# Mount Manually for the First Time
sudo mount -a

# Verify the Mount
df -h




================================================================
#
# Correcting /root/.ssh/authorized_keys file permissions
sudo chown root:root /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys

# Correcting /root directory permissions
sudo chown root:root /root
sudo chmod 700 /root




================================================================
import openai
import os

#gpt-3.5-turbo  4,096 tokens
#gpt-3.5-turbo-16k  16,385 tokens

# Set the API key from the environment variable
openai.api_key = os.getenv("OPENAI_API_KEY")

# Fetch the list of available models
available_models = openai.Engine.list()

# Filter and print out model names containing "gpt4"
for model in available_models['data']:
    if 'gpt' in model['id']:
        print(model['id'])
================================================================

import openai
import os

# Set the API key from the environment variable
openai.api_key = os.getenv("OPENAI_API_KEY")

# Fetch the list of available models
available_models = openai.Model.list()

# Filter and print out model names containing "gpt4"
for model in available_models['data']:
    if 'gpt' in model['id']:
        print(model['id'])

================================================================

pip install jupyter_ai_magics

%load_ext jupyter_ai_magics
%reload_ext jupyter_ai_magics

%%ai chatgpt
who are you
================================================================

import openai
import os
import interpreter as chatgpt
import interpreter

chatgpt.model = "gpt-3.5-turbo"
chatgpt.auto_run = True


api_key_main   = os.getenv("OPENAI_API_KEY")

api_key_backup = os.getenv("OPENAI_API_KEY_BACKUP")


def c(string):
    try:
        #         return chatgpt.chat(str(string))
        chatgpt.chat(str(string))
    except openai.error.RateLimitError as e:
        #         print("Rate limit error caught:", e)
        # print("Limit: 3 / min")
        chatgpt.api_key = api_key_backup
        chatgpt.chat(str(string))
        chatgpt.api_key = api_key_main
    except Exception as e:
        print(e)


def cc():
try    try:
        chatgpt.reset()
    except Exception as e:
        print(e)


================================================================
*/2 * * * *  cd /root/smart_bots && git pull && git add . && git commit -m  " `date` " && git push
*/3 * * * *  cd /root/vps && git pull && git add . && git commit -m  " `date` " && git push

@reboot sleep 7 ; bash -c "source ~/.bashrc;export PATH=/root/anaconda3/bin:$PATH; /root/anaconda3/bin/jupyter notebook --port=16666 --ip 0.0.0.0 --no-browser --allow-root --notebook-dir=/"

================================================================

wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib/
./configure --prefix=/usr
make
sudo make install

pip install freqtrade
================================================================
================================================================
"template": "$(python_version=$(command -v python >/dev/null 2>&1 && python --version 2>&1 | awk '{print $2}' || echo ''); conda_env=$(echo $CONDA_DEFAULT_ENV); if [ -z \"$conda_env\" ] && [ -z \"$python_version\" ]; then exit; else echo \" ($conda_env,$python_version)\"; fi)"

 ex it  style
================================================================
https://www.dongvps.com/2023-05-22/naiveproxy一键脚本更新如何正确的使用naive/

# 安装 naive命令
curl   https://raw.githubusercontent.com/imajeason/nas_tools/main/NaiveProxy/do.sh | bash
# 执行naive
naive

================================================================
Private key: YAjoKYIZ601zDTrYJKGoibA0bNTKCboCJNGUH7wgdn4
Public key: N9IY9bJiPgpe_1exP9LGkNHhqmbBL4tDbXc0lQEr9z8

https://github.com/zxcvos/Xray-script
Xray-REALITY 管理脚本
wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh


================================================================
优选WARP的EndPoint IP
https://github.com/getsomecat/GetSomeCats/blob/Surge/优选WARP的EndPoint%20IP，提高本地WARP节点访问性、修改官方客户端的EndPoint%20IP以及解锁ChatGPT.md
Linux 各发行版
wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-yxip/warp-yxip.sh && bash warp-yxip.sh

================================================================

https://github.com/P3TERX/warp.sh
Cloudflare WARP 一键安装脚本 使用教程
https://p3terx.com/archives/cloudflare-warp-configuration-script.html

================================================================
root@ja:/etc/wireguard# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 42:01:0a:b8:00:02 brd ff:ff:ff:ff:ff:ff
    altname enp0s4
    inet 10.184.0.2/24 brd 10.184.0.255 scope global ens4
       valid_lft forever preferred_lft forever
    inet6 fe80::4001:aff:feb8:2/64 scope link 
       valid_lft forever preferred_lft forever
8: warp: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none 
    inet 172.16.0.2/32 scope global warp
       valid_lft forever preferred_lft forever
    inet6 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128 scope global 
       valid_lft forever preferred_lft forever

root@ja:/etc/wireguard# cat warp.conf 
[Interface]
PrivateKey = +FGIX0vqalEDHX/dPUdYp9FCTKlHPiqoG7WC3kaGYl0=
Address = 172.16.0.2/32
Address = 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128
DNS = 1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844
MTU = 1420
PostUp = ip -4 rule add from 10.184.0.2 lookup main
PostDown = ip -4 rule delete from 10.184.0.2 lookup main

#Reserved = [164, 231, 38]
#Table = off
#PostUp = /etc/wireguard/NonGlobalUp.sh
#PostDown = /etc/wireguard/NonGlobalDown.sh

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0
#AllowedIPs = ::/0
Endpoint = 162.159.195.228:2371
PersistentKeepalive = 30

先wgcf 后 wg


PostUp =   iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o warp -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o warp -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o warp -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o warp -j MASQUERADE

================================================================

down 
wget -r -np -nH --cut-dirs=3 -R "index.html*" http://backup.jingyi.today/pdf_d/transformer_d2/pdf_txt_folder/



================================================================
# docker volume backup  and restore

# On VPS 1
# Create a backup of the volume
docker run --rm -v calibre_services_library_vol:/volume -v $(pwd):/backup ubuntu tar cvf /backup/calibre_volume_backup.tar -C /volume .

# Verify the backup file was created
ls -lh calibre_volume_backup.tar

# Optional: Check the contents of the backup (this doesn't extract the files)
tar tvf calibre_volume_backup.tar | head -n 10

############################################################

# On VPS 2
# Remove the existing volume
docker volume rm calibre_services_library_vol

# Create a new volume
docker volume create calibre_services_library_vol

# Restore the backup to the new volume
docker run --rm -v calibre_services_library_vol:/volume -v $(pwd):/backup ubuntu bash -c "tar xvf /backup/calibre_volume_backup.tar -C /volume"

# Verify the restored data
docker run --rm -v calibre_services_library_vol:/volume ubuntu ls -la /volume

# Check the volume size
docker run --rm -v calibre_services_library_vol:/volume ubuntu du -sh /volume



================================================================
