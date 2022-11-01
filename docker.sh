systemctl stop dokcer

apt install sudo -y
sudo apt-get -y purge docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd



sudo apt-get -y update
sudo apt-get -y install \
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

#docker ps -a

#apt-cache madison docker-ce
#sudo docker run hello-world 

# https://stackoverflow.com/questions/44678725/cannot-connect-to-the-docker-daemon-at-unix-var-run-docker-sock-is-the-docker
# Cannot connect to the Docker daemon at unix:/var/run/docker.sock. Is the docker daemon running?


#sudo dockerd
#sudo service --status-all 
#sudo service docker start
#sudo service docker start



docker ps  -a 
