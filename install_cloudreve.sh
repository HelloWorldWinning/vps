
mkdir -p /data

destination_folder="/data/Cloudreve"

mkdir -p $destination_folder

cd $destination_folder && \
mkdir -vp cloudreve/{uploads,avatar} \
&& touch cloudreve/conf.ini \
&& touch cloudreve/cloudreve.db \
&& mkdir -p aria2/config \
&& mkdir -p data/aria2 \
&& chmod -R 777 data/aria2



cat>>$destination_folder/docker-compose.yml<<EOF
version: "3.8"
services:
  redis:
    container_name: redis
    image: bitnami/redis:latest
    restart: unless-stopped
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
    volumes:
      - redis_data:/bitnami/redis/data

  cloudreve:
    container_name: cloudreve
    image: cloudreve/cloudreve:latest
    restart: unless-stopped
    ports:
      - "1111:5212"
    volumes:
      - temp_data:/data
      - ./cloudreve/uploads:/cloudreve/uploads
      - ./cloudreve/conf.ini:/cloudreve/conf.ini
      - ./cloudreve/cloudreve.db:/cloudreve/cloudreve.db
      - ./cloudreve/avatar:/cloudreve/avatar
    depends_on:
      - aria2

  aria2:
    container_name: aria2
    image: p3terx/aria2-pro # third party image, please keep notice what you are doing
    restart: unless-stopped
    ports:
      - "1112:6800"
    environment:
      - RPC_SECRET=weijingweiyi
      - RPC_PORT=6800
    volumes:
      - ./aria2/config:/config
      - temp_data:/data
volumes:
  redis_data:
    driver: local
  temp_data:
    driver: local
    driver_opts:
      type: none
      device: $PWD/data
      o: bind
EOF

apt install docker-compose -y

cd $destination_folder && \
docker-compose up -d

sleep 5

docker logs cloudreve | grep -E "Admin user name:|Admin password:" | awk -F': ' '{print $2}' > /root/cloudreve_admin_password.txt


cat /root/cloudreve_admin_password.txt
