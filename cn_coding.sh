#!/bin/bash

# Find all .txt files and convert their encoding from GBK to UTF-8
find . -type f -name "*.txt" | while read -r file; do
    iconv -f GBK -t UTF-8 "$file" > "${file%.txt}-utf8.txt"
done

