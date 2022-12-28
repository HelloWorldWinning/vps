docker run -d  --name 443  --restart=always  -p  443:443  \
-v /etc/nginx/conf.d/443.conf:/etc/nginx/conf.d/default.conf   \
-v /root/.acme.sh/febjp.hardeasy.top_ecc/febjp.hardeasy.top.key:/root/.acme.sh/febjp.hardeasy.top_ecc/febjp.hardeasy.top.key \
-v /root/.acme.sh/febjp.hardeasy.top_ecc/fullchain.cer:/root/.acme.sh/febjp.hardeasy.top_ecc/fullchain.cer \
  nginx  


docker run -d  --name 80  --restart=always  -p  80:80  \
-v /etc/nginx/conf.d/80.conf:/etc/nginx/conf.d/default.conf   \
 nginx  


docker exec -i -t  443 bash

