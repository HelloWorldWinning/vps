#!/usr/bin/bash

apt install markdown -y
#apt install markdown pandoc -y

de_path="/root/d.share"

mkdir -p  $de_path/md.d
mkdir -p  $de_path/html_md.d
#md=$(ls |grep  ".md$")
#html=$(ls |grep  ".html$")
md=$(ls $de_path/md.d |grep  ".md$" |cut -d "." -f1)
html=$(ls $de_path/html_md.d  |grep  ".html$" |cut -d "." -f1)
echo $md
echo $html
echo "=================="

md_arr=($md)

#html_arr=(html)

for i in ${!md_arr[@]}; do
   if [[ !  "$html"  =~  "${md_arr[$i]}"   ]]; then
   #if [[    "$html"  =~  ".*${md_arr[$i]}.*"   ]]; then
    echo  ${md_arr[$i]}.md
	markdown  $de_path/${md_arr[$i]}.md   >  $de_path/html_md.d/${md_arr[$i]}.html
   fi
done
