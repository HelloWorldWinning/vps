#!/bin/bash

## #!/usr/local/bin/bash
#/usr/local/bin/of

echo "networksetup -listallnetworkservices:default Ethernet;2 for Wi-Fi:,others input handy"
read -p ": " net_name
    if   [[ -z "$net_name" ]]; then
            net_name="Ethernet"

    elif [[  "$net_name" = 2 ]]; then
            net_name="Wi-Fi"
    else
	
	echo "input network_name :" $net_name
    fi


read -p "on / off: " on_off
    if   [[ -z "$on_off" ]]; then
            on_off="on"
    else
       on_off="off"
       networksetup -setsocksfirewallproxystate $net_name  off    
       networksetup -getsocksfirewallproxy $net_name
    exit 0
    fi


read -p "socket port default 31086:" ListenPort6
    if   [[ -z "$ListenPort6" ]]; then
            ListenPort6=31086
    fi


#echo "networksetup -listallnetworkservices:default Ethernet;2 for Wi-Fi:,others input handy"
#read -p ": " net_name
#    if   [[ -z "$net_name" ]]; then
#            net_name="Ethernet"
#
#    elif [[  "$net_name" = 2 ]]; then
#            net_name="Wi-Fi"
#    else
#	
#	echo "input network_name :" $net_name
#    fi




#echo $net_name $ListenPort6
#echo $on_off




#networksetup -setsocksfirewallproxy $net_name  127.0.0.1 "$ListenPort6"
#networksetup -setsocksfirewallproxystate $net_name  off    


 if   [[ $on_off = "on" ]]; then
          echo "open socket  on:" $net_name  "$ListenPort6"

networksetup -setsocksfirewallproxy $net_name  127.0.0.1 "$ListenPort6"
networksetup -getsocksfirewallproxy $net_name
fi


#    else
#        echo "close socket  on:" $net_name 
#
#       networksetup -setsocksfirewallproxystate $net_name  off    
#       networksetup -getsocksfirewallproxy $net_name
#    fi
