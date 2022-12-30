docker run -d  --name 443  --restart=always  -p  443:443  \
-v /etc/nginx/conf.d/443.conf:/etc/nginx/conf.d/default.conf   \
-v /root/.acme.sh/febjp.hardeasy.top_ecc/febjp.hardeasy.top.key:/root/.acme.sh/febjp.hardeasy.top_ecc/febjp.hardeasy.top.key \
-v /root/.acme.sh/febjp.hardeasy.top_ecc/fullchain.cer:/root/.acme.sh/febjp.hardeasy.top_ecc/fullchain.cer \
  nginx  


docker run -d  --name 80  --restart=always  -p  80:80  \
-v /etc/nginx/conf.d/80.conf:/etc/nginx/conf.d/default.conf   \
 nginx  


docker exec -i -t  443 bash



docker run -d   --name 33  --restart=always  -p  33:33  \
-v /home/rdp/Downloads/:/home/rdp/Downloads/  \
-v /data/ccaaDown/:/data/ccaaDown/  \
-v  /root/d.share/:/root/d.share/   \
-v /etc/nginx/conf.d/33.conf:/etc/nginx/conf.d/default.conf   \
nginx




docker run -d  --name $Port  --restart=always  -p  $Port:$Port  \
-v $cer_path:$cer_path \
-v $key_path:$key_path \
-v /etc/nginx/nginx.conf:/etc/nginx/nginx.conf \
-v  /root/d.share/:/root/d.share/  \
-v /home/rdp/Downloads/:/home/rdp/Downloads/  \
-v /data/ccaaDown/:/data/ccaaDown/  \
-v /etc/nginx/conf.d/${Port}.conf:/etc/nginx/conf.d/default.conf   \
nginx



apt install nginx-extras


aptitude install poppler-utils
pdftohtml -s  algo.pdf  index.html
pdftohtml -c  algo.pdf  index.html

