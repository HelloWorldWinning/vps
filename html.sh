echo "tree -H '.' -L 1 --noreport --charset utf-8 -o index.html"

echo "
    location /f/ {
    alias /root/shared/;     
    index index.html;
    }
"

#
#read -p 'level of tree default=1 =>': level ;
#[[ -z "${level}" ]] && level=1
#
#
#
#read -p 'path default current =>': path ;
#[[ -z "${path}" ]] && path=$(pwd)
#
#tree -H ${path} -L ${level} --noreport --charset utf-8 > ${path}/index.html
