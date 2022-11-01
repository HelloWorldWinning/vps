apt install sudo -y
sudo apt-get -y purge docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd



sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

#curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg


echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update   -y

sudo apt-get -y  install docker-ce docker-ce-cli containerd.io docker-compose-plugin

docker ps -a

#apt-cache madison docker-ce
#sudo docker run hello-world 
