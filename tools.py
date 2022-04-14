#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import time,json,sys
import shlex
import datetime
import subprocess
try: 
    from importlib import reload
except:
    pass

try:
    import urllib2
except:
    import urllib.request
    urllib2 = urllib.request


reload(sys)
try:
    sys.setdefaultencoding('utf-8')
except:
    pass

def GetIpipInfo(para):
    f = open("ip_json.json",'r')
    ijson = json.load(f)
    jjson = ijson['location']
    print( jjson[para.encode('utf-8')])

def GetGeoioInfo(para):
    ip_api = urllib2.urlopen(r'http://ip-api.com/json')
    ijson = json.loads(ip_api.read())
    print( ijson[para.encode('utf-8')] )
    
def GetDiskInfo(para):
    temp = ExecShell("df -h -P|grep '/'|grep -v tmpfs")[0];
    temp1 = temp.split('\n');
    diskInfo = [];
    n = 0
    cuts = ['/mnt/cdrom','/boot','/boot/efi','/dev','/dev/shm','/run/lock','/run','/run/shm','/run/user'];
    for tmp in temp1:
        n += 1
        disk = tmp.split();
        if len(disk) < 5: continue;
        if disk[1].find('M') != -1: continue;
        if disk[1].find('K') != -1: continue;
        if len(disk[5].split('/')) > 4: continue;
        if disk[5] in cuts: continue;
        arr = {}
        diskInfo = [disk[1],disk[2],disk[3],disk[4],disk[5]];

    print(diskInfo[int(para)]);

def ExecShell(cmdstring, cwd=None, timeout=None, shell=True):

    if shell:
       cmdstring_list = cmdstring
    else:
        cmdstring_list = shlex.split(cmdstring)
    if timeout:
        end_time = datetime.datetime.now() + datetime.timedelta(seconds=timeout)
        
    sub = subprocess.Popen(cmdstring_list, cwd=cwd, stdin=subprocess.PIPE,shell=shell,bufsize=4096,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        
    while sub.poll() is None:
        time.sleep(0.1)
        if timeout:
            if end_time <= datetime.datetime.now():
               raise Exception("Timeout：%s"%cmdstring)
                
    return sub.communicate()

if __name__ == "__main__":
    try:
        type = sys.argv[1]
    except:
        pass
    if type == 'disk':
        GetDiskInfo(sys.argv[2])
    elif type == 'geoip':
        try:
            GetGeoioInfo(sys.argv[2])
        except:
            pass
    elif type == 'ipip':
        try:
            GetIpipInfo(sys.argv[2])
        except:
            pass
    else:
        print( 'ERROR: Parameter error')
