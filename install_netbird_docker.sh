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





# --- Preflight: deregister existing peer, stop/remove container, delete image ---

# Fallback logger only if not already defined
if ! command -v log >/dev/null 2>&1; then
  log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
fi

# Ensure defaults exist even if this block is moved earlier accidentally
: "${CONTAINER_NAME:=netbird}"
: "${IMAGE:=netbirdio/netbird:latest}"
: "${VOLUME_NAME:=netbird-client}"

log "Preflight: attempting peer deregistration and cleanup for '${CONTAINER_NAME}'..."

# Helper: run netbird in a one-shot container against the persisted volume
nb_one_shot_deregister() {
  docker run --rm \
    -v "${VOLUME_NAME}:/var/lib/netbird" \
    "${IMAGE}" \
    sh -lc 'command -v netbird >/dev/null 2>&1 || ln -s /usr/local/bin/netbird /usr/bin/netbird 2>/dev/null || true; \
            netbird deregister || netbird logout || true'
}

# If the container exists, try deregister via exec; else try one-shot helper
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  log "Found existing container '${CONTAINER_NAME}'. Trying in-container deregistration..."
  if docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q '^true$'; then
    docker exec "${CONTAINER_NAME}" sh -lc 'netbird deregister || netbird logout || true' || true
  else
    log "Container is stopped; using one-shot helper against volume '${VOLUME_NAME}'..."
    nb_one_shot_deregister || true
  fi

  log "Stopping and removing container '${CONTAINER_NAME}'..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
else
  # No container—still try to deregister using the volume if present
  if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    log "No container found; using one-shot helper against volume '${VOLUME_NAME}'..."
    nb_one_shot_deregister || true
  fi
fi

# Remove the local image so we always pull fresh later
if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  log "Removing local image ${IMAGE}..."
  docker image rm -f "${IMAGE}" >/dev/null 2>&1 || true
fi

log "Preflight cleanup complete."
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


