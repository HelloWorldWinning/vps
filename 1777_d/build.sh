#!/bin/bash 

# Build the Docker image with a meaningful name
docker build -t oklove/port1777_md   .
docker push oklove/port1777_md
