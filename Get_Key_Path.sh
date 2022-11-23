

Acme_Get(){
curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
source ~/.bashrc
~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh   --issue -d $Domain --keylength ec-256 --force  --standalone --listen-v6
}

Get_Key_Path(){

echo "如果~/.acme.sh下没有正确的域名cer/key ，请确保80端口没有被占用，脚本自动获取域名"
  
read -p "请正确输入域名: " Domain
cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key

if [[ -f $cer_path ]]  && [[ -f $key_path ]]  ; then
echo $cer_path
echo $key_path

else

Acme_Get

cer_path=/root/.acme.sh/${Domain}_ecc/${Domain}.cer
key_path=/root/.acme.sh/${Domain}_ecc/${Domain}.key
echo $cer_path
echo $key_path

fi

}


Get_Key_Path
