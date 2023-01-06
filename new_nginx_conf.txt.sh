server {
    listen 443 ssl ;
    #listen [::]:443 ssl;
    server_name  chat.openai.com;

#    charset utf-8;
#    root /usr/share/nginx/html;
# index index.html index.htm index.html inde.php;
#
        ssl_certificate  /root/.acme.sh/ulovem.eu.org_ecc/fullchain.cer  ;
        ssl_certificate_key  /root/.acme.sh/ulovem.eu.org_ecc/ulovem.eu.org.key;

        #ssl_protocols TLSv1.2 TLSv1.3;
        #ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
        #client_header_timeout 52w;
        #keepalive_timeout 52w;

        location / {
        proxy_ssl_server_name on;
        proxy_pass https://chat.openai.com;
        proxy_set_header Host chat.openai.com;

proxy_set_header CF-Connecting-IP $remote_addr;
proxy_set_header CF-IPCountry $http_cf_ipcountry;

#proxy_set_header Accept-Encoding '';
#sub_filter "chat.openai.com" "ulovem.eu.org";
#sub_filter_once off;

}





}

=========

https://linuxhint.com/install-python-debian-10/ #How to Install Python on Debian 10

https://www.python.org/ftp/python/3.11.1/Python-3.11.1.tgz

cd Python-3.9.1
./configure --enable-optimizations
make -j  'nproc' # nproc  number of cpu
make altinstall




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







