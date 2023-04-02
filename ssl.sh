apt install dnsutils vim unzip  jq  net-tools  -y

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'



Acme_Get(){

curl -4  -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
source ~/.bashrc
~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
#~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
#~/.acme.sh/acme.sh   --issue -d $Domain --keylength 2048 --force  --standalone --listen-v6

}


get_ssl{

read  -p "input Domain" Domain
~/.acme.sh/acme.sh   --issue -d $Domain --keylength 2048    --standalone --listen-v6


}

menu() {
    clear
    echo "#############################################################"
    echo  "1 获取ssl file "
    echo 

    read -p " 请选择操作：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
		Acme_Get
		get_ssl
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

