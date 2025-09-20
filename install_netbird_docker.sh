#!/usr/bin/env bash
# install_netbird.sh
# - Container name: netbird
# - Uses host's hostname for the container (and thus NetBird peer name)
# - Ensures latest image (removes old image)
# - Runs with --network host so host can use the tunnel directly
# - Assumes Docker is installed and working; only manages "netbird"

set -euo pipefail

CONTAINER_NAME="netbird"
IMAGE="netbirdio/netbird:latest"
VOLUME_NAME="netbird-client"






# --- Preflight: only if a running 'netbird' exists ---

# Fallback logger only if not already defined
if ! command -v log >/dev/null 2>&1; then
  log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
fi

# Ensure defaults exist even if this block is moved earlier accidentally
: "${CONTAINER_NAME:=netbird}"
: "${IMAGE:=netbirdio/netbird:latest}"

# Proceed ONLY if the container is present AND running
if docker ps \
    --filter "name=^${CONTAINER_NAME}$" \
    --filter "status=running" \
    --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then

  log "Found running container '${CONTAINER_NAME}'. Deregistering and cleaning up..."

  # Best-effort deregistration from inside the running container
  docker exec "${CONTAINER_NAME}" sh -lc 'netbird deregister || netbird logout || true' || true

  # Stop & remove the container
  log "Stopping and removing container '${CONTAINER_NAME}'..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

  # Remove the local image so we always pull fresh later
  if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    log "Removing local image ${IMAGE}..."
    docker image rm -f "${IMAGE}" >/dev/null 2>&1 || true
  fi

  log "Preflight cleanup complete."
else
  log "No running '${CONTAINER_NAME}' found; skipping preflight."
fi
# --- end preflight ---




# You can override NB_SETUP_KEY by exporting it before running the script.
NB_SETUP_KEY="${NB_SETUP_KEY:-F52A5E7F-2A31-4390-9B15-4AF53172A1EA}"

HOST_HNAME="$(hostname)"
log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

if [[ -z "${NB_SETUP_KEY}" ]]; then
	echo "ERROR: NB_SETUP_KEY is empty. Export NB_SETUP_KEY or edit this script." >&2
	exit 1
fi

# Remove existing container if present (force stop + remove)
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
	log "Found existing container '${CONTAINER_NAME}'. Removing..."
	docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# Remove existing image to ensure we fetch the newest
if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
	log "Removing local image ${IMAGE} to pull the latest..."
	docker image rm -f "${IMAGE}" >/dev/null 2>&1 || true
fi

# Pull the newest image
log "Pulling ${IMAGE}..."
docker pull "${IMAGE}" >/dev/null

# Ensure persistent volume exists
if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
	log "Creating Docker volume '${VOLUME_NAME}'..."
	docker volume create "${VOLUME_NAME}" >/dev/null
fi

# Start the container with host networking so the tunnel is in the host namespace
log "Starting '${CONTAINER_NAME}' (host networking) with hostname '${HOST_HNAME}'..."
#--restart unless-stopped \

#--cap-add=NET_ADMIN \
docker run -d \
	--name "${CONTAINER_NAME}" \
        --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --cap-add=SYS_RESOURCE \
	--device /dev/net/tun \
	--network host \
	--hostname "${HOST_HNAME}" \
	-e NB_SETUP_KEY="${NB_SETUP_KEY}" \
	-v "${VOLUME_NAME}:/var/lib/netbird" \
	--restart always \
	"${IMAGE}" \
	sh -c "sleep 20; exec /usr/local/bin/netbird service run"

# Show quick status
log "Container '${CONTAINER_NAME}' started."
docker ps --filter "name=^${CONTAINER_NAME}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

# Helpful checks
echo
log "Quick checks you can run:"
echo "  ip addr show wt0            # Interface should now be on the HOST"
echo "  ip route | grep 100.        # Routes for NetBird range should be present"
# echo "  ping -c 3 100.105.160.165   # Ping your US peer's NetBird IP from HOST"

ip route | grep 100


