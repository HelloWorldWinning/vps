docker run --name="ccaa" -d  --restart=always    -p 6080:6080 -p 6081:6081 -p 6800:6800 -p 51413:51413 \
    -v /data/ccaaDown:/data/ccaaDown\
    -e PASS="a" \
    helloz/ccaa \
    sh -c "dccaa pass && dccaa start"
