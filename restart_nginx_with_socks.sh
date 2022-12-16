
Un_Links() {

grep  ".sock\|.socket" /etc/nginx/conf.d/*.conf |xargs -I {}  echo {} |grep -v "#" |cut -d":" -f3 | tr -d ";"|cut -d" " -f1 |xargs -I {} unlink {}

#grep .socket /etc/nginx/conf.d/*.conf |grep grpc_pass  |xargs -I {}  echo {} |cut -d":" -f3 | tr -d ";" |xargs -I {} unlink {}
#grep  ".sock\|.socket" /etc/nginx/conf.d/*.conf |xargs -I {}  echo {} |grep -v "#" |cut -d":" -f3 | tr -d ";" |xargs -I {} unlink {}
}

Restart_Ng_under_links() {
systemctl reload nginx
systemctl restart nginx
systemctl stop nginx
Un_Links
systemctl restart nginx
systemctl status nginx
}
