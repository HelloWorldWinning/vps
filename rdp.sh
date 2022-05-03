# https://zhuanlan.zhihu.com/p/76991840  安装Debian并开启远程桌面（通过Xorg）
read -p 'input rdp user name[rdp for empty]': rdp_username 
if [[ -z "${rdp_username}" ]] ; then
 rdp_username=rdp
else
rdp_username=$rdp_username
fi
sudo adduser ${rdp_username}

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g"  /etc/ssh/sshd_config
sudo systemctl restart sshd
sudo apt-get install net-tools xrdp xfce4 tigervnc-standalone-server

echo xfce4-session>/home/${rdp_username}/.xsession

sudo wget -O google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo apt install ./google-chrome-stable_current_amd64.deb -y
