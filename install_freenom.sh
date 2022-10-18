#docker run -d --name freenom --restart always -v $(pwd):/conf -v $(pwd)/logs:/app/logs -e RUN_AT="04:50" luolongfei/freenom
docker run -d --name freenom --restart always -v $(pwd):/conf -v $(pwd)/logs:/app/logs   luolongfei/freenom

#wget  -O /root/.env  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/env_freenom.txt

#wget -O /root/.env  --header "Authorization: token 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" https://raw.githubusercontent.com/HelloWorldWinning/vps_private/main/env_freenom.txt?token=GHSAT0AAAAAAB2CDARNMWBH4IIHVIPF35FMY2N7THQ

#wget  -O /root/.env  --header "Authorization:token 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"  -r  "https://raw.githubusercontent.com/HelloWorldWinning/vps_private/main/env_freenom.txt?token=GHSAT0AAAAAABYTXSAAZFGPNS7QLYUC5JTYY2ODB7A"

wget  -O /root/.env   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/env_freenom.txt

read -p 'password for freenom.com':FNpassword;

sed -i 's/RepLAce/${FNpassword}/g' /root/.env

docker restart freenom
sleep 9
docker logs freenom
