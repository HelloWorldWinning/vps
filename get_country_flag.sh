#!/bin/bash
echo -e "\\U$(printf '%x' $(($(printf '%d' "'${country_code:0:1}") + 127397)))\\U$(printf '%x' $(($(printf '%d' "'${country_code:1:1}") + 127397)))"
