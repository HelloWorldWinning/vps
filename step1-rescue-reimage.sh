#!/usr/bin/env bash
# Reimage a VirtFusion VPS from its independent Rescue environment.
# Debian 13 point releases are selected through trixie/latest; no point release is hardcoded.

set -Eeuo pipefail

TARGET_DISK="${1:-/dev/vda}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-trixie}"
DEBIAN_MAJOR="${DEBIAN_MAJOR:-13}"
IMAGE_NAME="debian-${DEBIAN_MAJOR}-genericcloud-amd64.qcow2"
BASE_URL="https://cloud.debian.org/images/cloud/${DEBIAN_CODENAME}/latest"
WORK_DIR="/tmp/debian-${DEBIAN_MAJOR}-reimage"
IMAGE_PATH="${WORK_DIR}/${IMAGE_NAME}"
CHECKSUM_PATH="${WORK_DIR}/SHA512SUMS"
CIDATA_MOUNT="/mnt/vf-cidata-check"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if mountpoint -q "$CIDATA_MOUNT" 2>/dev/null; then
        umount "$CIDATA_MOUNT" || true
    fi
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || die "Run this script as root."
[[ -e /run/live/medium ]] || die "This does not appear to be the VirtFusion Rescue environment."

for tool in blkid blockdev curl findmnt grep lsblk mountpoint numfmt qemu-img sha512sum sync udevadm wipefs; do
    command -v "$tool" >/dev/null 2>&1 || die "Required tool is missing: $tool"
done

[[ -b $TARGET_DISK ]] || die "Target is not a block device: $TARGET_DISK"
[[ $(lsblk -dnro TYPE "$TARGET_DISK") == disk ]] || die "Target is not a whole disk: $TARGET_DISK"
[[ $(blockdev --getro "$TARGET_DISK") == 0 ]] || die "Target disk is read-only: $TARGET_DISK"

while IFS= read -r device; do
    if findmnt -rn -S "$device" >/dev/null 2>&1; then
        die "Target device is mounted: $device"
    fi
done < <(lsblk -lnpo NAME "$TARGET_DISK")

CIDATA_DEVICE="$(blkid -L cidata 2>/dev/null || true)"
[[ -n $CIDATA_DEVICE ]] || die "VirtFusion cloud-init drive with label 'cidata' was not found. Keep Auto Configuration enabled."

mkdir -p "$CIDATA_MOUNT"
mount -o ro "$CIDATA_DEVICE" "$CIDATA_MOUNT"
for file in user-data meta-data network-config; do
    [[ -f "$CIDATA_MOUNT/$file" ]] || die "Cloud-init file is missing: $file"
done

SSH_KEY_COUNT="$(grep -Eoc 'ssh-(ed25519|rsa|ecdsa)' "$CIDATA_MOUNT/user-data" || true)"
[[ $SSH_KEY_COUNT -ge 1 ]] || die "No SSH public key was found in VirtFusion user-data. Add a key before reimaging."
umount "$CIDATA_MOUNT"

printf '\nRescue environment confirmed.\n'
printf 'Target disk: %s (%s)\n' "$TARGET_DISK" "$(blockdev --getsize64 "$TARGET_DISK" | numfmt --to=iec)"
printf 'Cloud-init: %s, %s SSH public key(s)\n' "$CIDATA_DEVICE" "$SSH_KEY_COUNT"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$TARGET_DISK"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

printf '\nDownloading the latest Debian %s (%s) generic-cloud image...\n' "$DEBIAN_MAJOR" "$DEBIAN_CODENAME"
curl --fail --location --retry 3 --progress-bar --output "$IMAGE_PATH" "$BASE_URL/$IMAGE_NAME"
curl --fail --location --retry 3 --silent --show-error --output "$CHECKSUM_PATH" "$BASE_URL/SHA512SUMS"

CHECKSUM_LINE="$(grep -E "[[:space:]](\./)?${IMAGE_NAME}$" "$CHECKSUM_PATH" || true)"
[[ -n $CHECKSUM_LINE ]] || die "The image is not listed in Debian's SHA512SUMS."
printf '%s\n' "$CHECKSUM_LINE" | sed "s# \./${IMAGE_NAME}\$#  ${IMAGE_NAME}#" | sha512sum --check -
qemu-img check -f qcow2 "$IMAGE_PATH"
qemu-img info "$IMAGE_PATH"

printf '\nWARNING: This permanently erases %s and all of its data.\n' "$TARGET_DISK"
printf 'The verified official Debian image will replace the existing system.\n'
read -r -p "Type exactly ERASE ${TARGET_DISK} to continue: " CONFIRM </dev/tty
[[ $CONFIRM == "ERASE ${TARGET_DISK}" ]] || die "Cancelled; nothing was written."

printf '\nClearing old disk signatures...\n'
wipefs --all "$TARGET_DISK"

printf 'Writing Debian %s to %s...\n' "$DEBIAN_MAJOR" "$TARGET_DISK"
qemu-img convert -p -f qcow2 -O raw "$IMAGE_PATH" "$TARGET_DISK"
sync
blockdev --rereadpt "$TARGET_DISK" 2>/dev/null || true
command -v partprobe >/dev/null 2>&1 && partprobe "$TARGET_DISK" 2>/dev/null || true
udevadm settle

printf '\nNew disk layout:\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,MOUNTPOINTS "$TARGET_DISK"
command -v fdisk >/dev/null 2>&1 && fdisk -l "$TARGET_DISK" || true

cat <<EOF

IMAGE WRITE COMPLETE

Next actions in VirtFusion:
  1. Keep Auto Configuration enabled.
  2. Keep HDD first in the boot order.
  3. End the Rescue session; do not merely reboot Rescue.
  4. Wait 2-3 minutes, then SSH to the configured root account using its key.

After normal Debian boots, run step2-normal-finalize.sh.
EOF
