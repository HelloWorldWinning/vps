# https://zhuanlan.zhihu.com/p/76991840  安装Debian并开启远程桌面（通过Xorg）
# https://linuxize.com/post/how-to-install-xrdp-on-debian-10/  How to Install Xrdp Server (Remote Desktop) on Debian 10
read -p 'input rdp user name[rdp for empty]': rdp_username 
if [[ -z "${rdp_username}" ]] ; then
 rdp_username=rdp
else
rdp_username=$rdp_username
fi
sudo adduser ${rdp_username}
sudo adduser ${rdp_username} ssl-cert  

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g"  /etc/ssh/sshd_config
sudo systemctl restart sshd

sudo apt update -y
#sudo apt-get install net-tools xrdp xfce4 tigervnc-standalone-server -y
# sudo apt install xfce4 xfce4-goodies xorg dbus-x11 x11-xserver-utils -y
sudo apt install net-tools  xfce4 tigervnc-standalone-server  xfce4-goodies xorg dbus-x11 x11-xserver-utils   -y
sudo apt install xrdp -y


echo xfce4-session>/home/${rdp_username}/.xsession

sudo wget -O google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo apt install ./google-chrome-stable_current_amd64.deb -y

sudo systemctl status xrdp
