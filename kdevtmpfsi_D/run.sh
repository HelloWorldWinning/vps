#!/bin/bash
#
#https://askubuntu.com/questions/1225410/my-ubuntu-server-has-been-infected-by-a-virus-kdevtmpfsi
#https://stackoverflow.com/questions/60151640/kdevtmpfsi-using-the-entire-cpu
#https://www.enmimaquinafunciona.com/pregunta/174372/mi-servidor-ubuntu-ha-sido-infectado-por-un-virus-kdevtmpfsi


report=/var/log/incident.log
if [  -f "$report" ]
then
echo
else
touch $report
fi
chattr +i /tmp/kdevtmpfsi
chmod 000 /tmp/zzz
fixing () {
rm -rfv /tmp/kdevtmpfsi*
touch /tmp/kdevtmpfsi
rm -rfv /tmp/cron*
kill -9 $((ps -aux | grep -i 'kdevtmpfsi\|kinsing') 2>/dev/null |grep -v grep |awk '{print $2}')
cat /var/spool/cron/zimbra |grep -i unk.sh && rm -rfv /var/spool/cron/zimbra
kin=$(ls /opt/zimbra/log/ |grep -i kinsing) && rm -rfv /opt/zimbra/log/${kin}
}
log () {
 echo  "$(date) by user:$(whoami) executed:<$0> virus:kdevtmpfsi action:>killed Pattern:spoofing Target:<CPU> host:$(hostname):<$(curl -s ident.me)>" >> $report
}
fixing

log


