# Stop and remove any running container
docker compose down -v || true
docker rm -f file_recv_api 2>/dev/null || true

# Delete the old image tag so we're sure we don't reuse it
docker rmi oklove/file-recv-api:latest 2>/dev/null || true

# Build fresh (no cache)
docker build --no-cache -t oklove/file-recv-api:latest .

# (Optional) Sanity check binary exists inside the image
docker run --rm --entrypoint /bin/sh oklove/file-recv-api:latest -lc 'ls -lh /usr/local/bin/file-recv-api'

#docker push oklove/file-recv-api:latest
