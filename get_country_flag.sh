#!/bin/bash

if [[ -f /etc/debian_version ]] && [[ $(cat /etc/debian_version | cut -d. -f1) == "13" ]]; then
	echo $country_code
else
	echo -e "\\U$(printf '%x' $(($(printf '%d' "'${country_code:0:1}") + 127397)))\\U$(printf '%x' $(($(printf '%d' "'${country_code:1:1}") + 127397)))"
fi
