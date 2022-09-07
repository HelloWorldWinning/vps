while true; do
   read -p 'input 6/12 code->' credit
 if  [ -z "$credit" ] ; then
        echo "input again "
        continue
    else
       curl -sSLH "Accept-Version: 5" "https://lookup.binlist.net/$credit"|jq
    fi
done

