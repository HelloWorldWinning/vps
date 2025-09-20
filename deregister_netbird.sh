#!/usr/bin/env bash
# Deregister NetBird:
# - If Docker has containers matching "netbird":
#     * For each running one: run "netbird deregister" inside it, then stop & rm it.
#     * Afterwards, try to "docker image rm" images of removed containers (only if unused).
# - Else (or Docker unavailable): run "netbird deregister" on the host.
set -Eeuo pipefail

log() { printf '[netbird-deregister] %s\n' "$*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

run_netbird_deregister() {
	if command -v netbird >/dev/null 2>&1; then
		netbird deregister
		return
	fi
	for p in /usr/bin/netbird /usr/local/bin/netbird /bin/netbird; do
		if [ -x "$p" ]; then
			"$p" deregister
			return
		fi
	done
	return 127
}

docker_deregister_in_container() {
	# $1 = container ID
	local cid="$1"
	docker exec "$cid" sh -lc '
    set -e
    if command -v netbird >/dev/null 2>&1; then
      netbird deregister
    elif [ -x /usr/bin/netbird ]; then
      /usr/bin/netbird deregister
    elif [ -x /usr/local/bin/netbird ]; then
      /usr/local/bin/netbird deregister
    else
      echo "netbird binary not found in container" >&2
      exit 127
    fi
  '
}

docker_stop_and_rm() {
	# $1 = container ID
	local cid="$1"
	# Stop only if running (avoids noisy error)
	if [ "$(docker inspect -f '{{.State.Running}}' "$cid")" = "true" ]; then
		log "Stopping container $cid ..."
		docker stop -t 10 "$cid" >/dev/null
	fi
	log "Removing container $cid ..."
	docker rm "$cid" >/dev/null
}

docker_branch() {
	# Find matching containers (ID Image Name)
	local lines
	if ! lines=$(docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null); then
		return 1
	fi

	# Match anything with "netbird" in image or name (case-insensitive)
	local matches
	matches=$(printf '%s\n' "$lines" | grep -iE '(^|\s|/)(netbird)($|\s|:|/)' || true)
	[ -z "$matches" ] && {
		log "No Docker containers matching 'netbird'."
		return 3
	}

	log "Found Docker container(s) matching 'netbird'."
	# Track images for containers we actually remove
	declare -a images_to_remove=()
	local removed_count=0 dereg_count=0

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		local cid image name
		cid=$(awk '{print $1}' <<<"$line")
		image=$(awk '{print $2}' <<<"$line")
		name=$(awk '{print $3}' <<<"$line")

		local running
		running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)"

		if [ "$running" = "true" ]; then
			log "Deregistering inside running container ${name:-$cid} ..."
			if docker_deregister_in_container "$cid"; then
				dereg_count=$((dereg_count + 1))
				# Capture the immutable image ID so we can safely rm later
				local image_id
				image_id="$(docker inspect -f '{{.Image}}' "$cid")"
				# Stop & remove this container
				docker_stop_and_rm "$cid"
				removed_count=$((removed_count + 1))
				images_to_remove+=("$image_id")
			else
				log "WARN: Failed to deregister in ${name:-$cid}; skipping removal."
			fi
		else
			log "Container ${name:-$cid} is not running; skipping deregister. (No changes made.)"
			# If you want to also clean up stopped containers, remove the line above and uncomment below:
			# docker_stop_and_rm "$cid"; images_to_remove+=("$(docker inspect -f '{{.Image}}' "$cid")"); removed_count=$((removed_count+1))
		fi
	done <<<"$matches"

	# Deduplicate images and try to remove any that are no longer used
	if [ "${#images_to_remove[@]}" -gt 0 ]; then
		log "Attempting to remove images of removed container(s) if unused..."
		mapfile -t uniq_imgs < <(printf '%s\n' "${images_to_remove[@]}" | sort -u)
		for img in "${uniq_imgs[@]}"; do
			# Skip if any container still references this image
			if [ -n "$(docker ps -a -q --filter "ancestor=$img")" ]; then
				log "Image $img still in use by other container(s); not removing."
				continue
			fi
			if docker image rm "$img" >/dev/null 2>&1; then
				log "Removed image $img."
			else
				log "Could not remove image $img (may be tagged multiple times or in use)."
			fi
		done
	fi

	log "Deregistered in $dereg_count container(s); removed $removed_count container(s)."
	# Succeed if we did anything meaningful
	[ "$dereg_count" -gt 0 ] && return 0 || return 2
}

host_branch() {
	log "Falling back to host: attempting 'netbird deregister' on this machine..."
	if run_netbird_deregister; then
		log "Host deregistration succeeded."
		return 0
	else
		log "ERROR: netbird binary not found on host."
		return 127
	fi
}

main() {
	if have_cmd docker; then
		if docker_branch; then
			exit 0
		else
			host_branch
		fi
	else
		host_branch
	fi
}

main "$@"
