#!/bin/bash

Path_AFFiNE='/root/AFFiNE_D'
mkdir -p $Path_AFFiNE/self-host/{config,storage,redis,postgres}

###curl -fSsL4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/compose_yml_AFFiNE.yml -o $Path_AFFiNE/compose.yml
curl  -o  $Path_AFFiNE/compose.yml       -fSsL4   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/compose_yml_AFFiNE.yml

cd $Path_AFFiNE
docker compose up -d

sleep 5

echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep "affine"

sleep 4


bash <(curl -fSsL4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/AFFine_increase_AFFine_Cloud_Storage.sh )
