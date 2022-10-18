#docker run -d --name freenom --restart always -v $(pwd):/conf -v $(pwd)/logs:/app/logs -e RUN_AT="04:50" luolongfei/freenom
docker run -d --name freenom --restart always -v $(pwd):/conf -v $(pwd)/logs:/app/logs   luolongfei/freenom

#wget  -O /root/.env  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/env_freenom.txt

wget -O /root/.env  --header "Authorization: token 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" https://raw.githubusercontent.com/HelloWorldWinning/vps_private/main/env_freenom.txt?token=GHSAT0AAAAAAB2CDARNMWBH4IIHVIPF35FMY2N7THQ

docker restart freenom
sleep 9
docker logs freenom
