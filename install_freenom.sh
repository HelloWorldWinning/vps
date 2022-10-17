docker run -d --name freenom --restart always -v $(pwd):/conf -v $(pwd)/logs:/app/logs -e RUN_AT="04:50" luolongfei/freenom

wget  -O /root/.env  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/env_freenom.txt

docker restart freenom
sleep 5
docker logs freenom
