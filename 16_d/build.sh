#!/bin/bash 

# Build the Docker image with a meaningful name
docker build -t oklove/port16_py_jupyter   .
docker push oklove/port16_py_jupyter
