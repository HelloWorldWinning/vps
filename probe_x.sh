 while true
        do
            read -p "database PassWord" PassWord
            if [[ -z "${PassWord}" ]]; then
                colorEcho " 必须输入"
            else
                break
            fi
        done


docker pull mysql

mkdir -p /home/mysql

docker run -d --name=mysql \
  -v /home/mysql/data:/var/lib/mysql \
  -v /home/mysql/conf.d:/etc/mysql/conf.d \
  -v /home/mysql/logs:/var/logs/mysql \
  -e MYSQL_DATABASE=mynodequery \
  -e MYSQL_USER="1" \
  -e MYSQL_PASSWORD="${PassWord}" \
  -e MYSQL_RANDOM_ROOT_PASSWORD="${PassWord}" \
  -p 3306:3306 \
  --restart=always \
  mysql 




#######################

mkdir -p /etc/mynodequery/
cat >/etc/mynodequery/appsettings.json<<EOF
{
 "Logging": {
     "LogLevel": {
         "Default": "Information",
         "Microsoft": "Warning",
         "Microsoft.Hosting.Lifetime": "Information"
     }
 },
 "MySql": {
     "ConnectionString": ""
 },
 "AllowedHosts": "*",
 "Installed": "false",
 "ReadNodeIpHeaderKey": "X-Real-IP"
}
EOF


#docker run -d --name=mynodequery \
#  --link=mysql57:mysql57 \
#  -p 5000:5000 \
#  -v /home/mynodequery/appsettings.json:/app/appsettings.json \
#  --restart=always \
#  jaydenlee2019/mynodequery:latest


docker run -d --name=mynodequery -p 5000:5000 -v /etc/mynodequery/appsettings.json:/app/appsettings.json jaydenlee2019/mynodequery:latest
