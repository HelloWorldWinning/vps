net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)
ip_inet=$(ifconfig $net_card|grep inet|grep  -v inet6| awk '{print $2}')
echo $ip_inet
cat >>/etc/hosts<<EOF
$ip_inet  $HOSTNAME
EOF



apt update -y
apt install sudo curl wget  -y
sudo apt-get update -y
sudo apt-get install net-tools xrdp xfce4 tigervnc-standalone-server -y




sudo service xrdp stop

read -p 'input rdp port(default 33389)': rdp_port_input
if [[ -z "${rdp_port_input}" ]] ; then
 rdp_port=33389
else
rdp_port=$rdp_port_input
fi

sudo sed -i "s/port=3389/port=${rdp_port}/g" /etc/xrdp/xrdp.ini

sudo service xrdp restart



read -p 'input rdp user name[rdp for empty]': rdp_username_input
if [[ -z "${rdp_username_input}" ]] ; then
 rdp_username=rdp
else
 rdp_username=$rdp_username_input
fi
sudo adduser ${rdp_username}
sudo adduser ${rdp_username} ssl-cert  
cat  >>/etc/sudoers<<EOF 
${rdp_username} ALL=(ALL:ALL) ALL
EOF



echo xfce4-session>/home/${rdp_username}/.xsession

sudo wget -O google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

sudo apt install ./google-chrome-stable_current_amd64.deb -y



sudo apt-get install aptitude  -y 
sudo aptitude  install  firefox-esr -y





# https://blog.51cto.com/u_15060545/3936030  Debian 9.5 解决中文显示乱码
 
echo "en_US.UTF-8 zh_CN.UTF-8 ← 选择 chose "
echo "locale zh_CN.UTF-8 ← 选择 chose  "

sleep 3

sudo apt-get install locales -y

# 安装字体
apt-get install ttf-wqy-zenhei -y
# 安装输入法
apt-get install ibus ibus-gtk ibus-pinyin -y




cat >>/etc/X11/app-defaults/XTerm<<EOF
xterm*faceName: Andale Mone
xterm*faceSize: 25

xterm*background: black
!xterm*background: Grey11

xterm*foreground: Green3
!xterm*foreground: #2f6941
EOF

 
#xterm*faceName: Monospace
#xterm*faceSize: 22
#XTerm*background: lightblack
#XTerm*foreground: lightgreen



 
# microsoft-edge  https://www.linuxcapable.com/how-to-install-microsoft-edge-on-debian-11/


sudo apt update && sudo apt upgrade -y
sudo apt install software-properties-common apt-transport-https wget ca-certificates gnupg2 ubuntu-keyring -y
sudo wget -O- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-edge.gpg
echo 'deb [signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main' | sudo tee /etc/apt/sources.list.d/microsoft-edge.list
sudo apt update
sudo apt install microsoft-edge-stable -y




cat >>/etc/X11/app-defaults/XTerm<<EOF
xterm*faceName: Andale Mone
xterm*faceSize: 22
XTerm*background: lightblack
XTerm*foreground: lightgreen
EOF

  
wget http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8_all.deb
sudo dpkg -i ttf-mscorefonts-installer_3.8_all.deb
sudo apt install  cabextract -y
sudo apt --fix-broken install  -y
sudo apt autoremove -y
sudo apt-get install ttf-mscorefonts-installer -y







##########################################################################################################################################







#echo gnome-session>/home/${rdp_username}/.xsession 不要这太臃肿

## https://zhuanlan.zhihu.com/p/76991840  安装Debian并开启远程桌面（通过Xorg）
## https://linuxize.com/post/how-to-install-xrdp-on-debian-10/  How to Install Xrdp Server (Remote Desktop) on Debian 10
#read -p 'input rdp user name[rdp for empty]': rdp_username 
#if [[ -z "${rdp_username}" ]] ; then
# rdp_username=rdp
#else
#rdp_username=$rdp_username
#fi
#sudo adduser ${rdp_username}
#sudo adduser ${rdp_username} ssl-cert  
#
#sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g"  /etc/ssh/sshd_config
#sudo systemctl restart sshd
#
#sudo apt update -y
##sudo apt-get install net-tools xrdp xfce4 tigervnc-standalone-server -y
## sudo apt install xfce4 xfce4-goodies xorg dbus-x11 x11-xserver-utils -y
#sudo apt install net-tools  xfce4 tigervnc-standalone-server  xfce4-goodies xorg dbus-x11 x11-xserver-utils   -y
#sudo apt install xrdp -y
#
#
#echo xfce4-session>/home/${rdp_username}/.xsession
#
#sudo wget -O google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#
#sudo apt install ./google-chrome-stable_current_amd64.deb -y
#
#sudo cat  >>/etc/sudoers<<EOF 
#${rdp_username}   ALL=(ALL:ALL) ALL
#EOF
#
#
#
#sudo systemctl status xrdp
#
