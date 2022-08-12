echo "
    location /f/ {
    alias /root/shared/;     
    index index.html;
    }
"

echo "
tree -H '.' -L 1 --noreport --charset utf-8 -o index.html
"

read -p 'level of tree default=1 =>' level ;
[[ -z "${level}" ]] && level=1

tree -H '.' -L  ${level}  --noreport --charset utf-8 -o index.html





#read -p 'path default current =>' path ;
#[[ -z "${path}" ]] && path=$(pwd)
#tree -H '.'  -L ${level} --noreport --charset utf-8 > ${path}/index.html
