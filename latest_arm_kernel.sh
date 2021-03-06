cat  >>/etc/apt/sources.list<<EOF  
deb http://deb.debian.org/debian bullseye-backports main contrib non-free
EOF

echo "deb http://deb.debian.org/debian bullseye-backports main" >/etc/apt/sources.list.d/bullseye-backports.list

apt update
apt upgrade -y
# apt -t bullseye-backports install linux-image-amd64 linux-headers-amd64 -y
apt -t bullseye-backports install linux-image-arm64 linux-headers-arm64 -y


# Last_Version=$(apt-cache search linux-image  |grep arm64|grep v8|grep -v rt  |grep -v meta|grep -v unsigned|grep -v trunk|sort| tail -1 |awk '{print $1; exit}')
# echo $Last_Version
# apt -t bullseye-backports install $Last_Version
# linux-image-5.16.0-0.bpo.4-arm64
# version=$(echo  $Last_Version | cut -d "-" -f 3)
# echo $version
# header=$(apt-cache search linux-header  |grep $version |grep -v rt|grep arm64|grep -v cloud|tail -1|awk '{print $1; exit}')
# echo $header
# apt -t bullseye-backports install $header
