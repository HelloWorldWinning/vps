#!/usr/bin/env bash
# minimal install/update for linuxserver/webtop at /root/webtop_d

set -euo pipefail

DIR="/root/webtop_d"
SERVICE="webtop"
IMAGE="lscr.io/linuxserver/webtop:latest"

compose_cmd() {
	if docker compose version >/dev/null 2>&1; then
		echo "docker compose"
	elif command -v docker-compose >/dev/null 2>&1; then
		echo "docker-compose"
	else
		echo "ERROR: Docker Compose not found (install docker compose plugin or docker-compose)." >&2
		exit 1
	fi
}

DC="$(compose_cmd)"
mkdir -p "$DIR"

# --- write your exact docker-compose.yml ---
cat >"$DIR/docker-compose.yml" <<'YAML'
services:
  webtop:
    image: lscr.io/linuxserver/webtop:latest
    container_name: webtop
    security_opt:
      - seccomp:unconfined # optional, helps some desktop apps on older hosts
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Tokyo
      - CUSTOM_USER=a
      - PASSWORD=a
      - SUBFOLDER=/           # optional
      - TITLE=Webtop          # optional
    volumes:
      - ./webtop-config:/config
      # - /var/run/docker.sock:/var/run/docker.sock  # optional: manage host Docker from Webtop
      # - /dev/dri:/dev/dri                          # optional: GPU acceleration on open-source drivers
    ports:
#      - "3000:3000"  # HTTP (for reverse proxy only; browser access should use HTTPS)
#     - "3001:3001"  # HTTPS (self-signed)
      - "8300:3000"  # HTTP
    shm_size: "1gb"   # optional, keeps modern browsers from crashing
    restart: unless-stopped
YAML

# ensure config dir exists
mkdir -p "$DIR/webtop-config"

# detect if container exists
container_exists=false
if docker ps -a --format '{{.Names}}' | grep -qx "$SERVICE"; then
	container_exists=true
fi

# get current running image ID (if any)
current_id="$(docker inspect -f '{{.Image}}' "$SERVICE" 2>/dev/null || true)"

# record the local tag's image id before pull (if present)
before_pull_id="$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)"

# check remote by pulling tag (fast if already up-to-date)
echo "Checking for updates to $IMAGE ..."
docker pull "$IMAGE" >/dev/null

# get the tag's image id after pull
after_pull_id="$(docker image inspect "$IMAGE" -f '{{.Id}}' 2>/dev/null || true)"

cd "$DIR"

if "$container_exists"; then
	if [[ -n "$current_id" && -n "$after_pull_id" && "$current_id" == "$after_pull_id" ]]; then
		echo "✅ $IMAGE is already the latest. Container uses the newest image. No changes made."
		exit 0
	else
		echo "⬆️  Newer image detected (or container not on latest). Recreating ..."
		$DC down
		if [[ -n "$current_id" && "$current_id" != "$after_pull_id" ]]; then
			# remove old image ID (ignore errors if already untagged)
			docker image rm -f "$current_id" >/dev/null 2>&1 || true
		fi
		$DC up -d
		echo "✅ Updated to the latest image and started."
	fi
else
	echo "🚀 First-time start (no existing container)."
	$DC up -d
	echo "✅ Started."
fi
