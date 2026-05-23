#!/usr/bin/env bash
set -euo pipefail

docker build --no-cache -t oklove/webpage_port_7788_download .
docker push oklove/webpage_port_7788_download
