#!/bin/bash
set -euo pipefail

# Build the Docker image with a meaningful name
IMAGE="oklove/file-recv-api:latest"

# (Optional) Ensure bases are present locally
docker pull rust:slim-trixie
docker pull debian:trixie-slim

docker build -t "$IMAGE" .
echo "Built $IMAGE"
