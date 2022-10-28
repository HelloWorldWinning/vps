# https://nginx.org/en/linux_packages.html
# https://dream.ren/nginx_stream.html

apt install -y sudo  curl
apt-get install -y  sudo  curl 

sudo apt install curl gnupg2 ca-certificates lsb-release debian-archive-keyring


curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg


cat >>/etc/hosts<<EOF
$(ip route get 1.2.3.4 | awk '{print $7}')   $('hostname'  )
EOF

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/debian `lsb_release -cs` nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list


#echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list


echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx



sudo apt update
sudo apt install nginx


