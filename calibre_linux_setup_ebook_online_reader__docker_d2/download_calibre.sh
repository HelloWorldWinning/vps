#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="${1:?Usage: $0 <calibre_version>}"
ARCH="${CALIBRE_ARCH:-x86_64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"

FILE="calibre-${VERSION}-${ARCH}.txz"
SHA_FILE="${FILE}.sha512"

URL="https://download.calibre-ebook.com/${VERSION}/${FILE}"
SHA_URL="https://calibre-ebook.com/signatures/${SHA_FILE}"

TARGET="${DOWNLOAD_DIR}/${FILE}"
SHA_TARGET="${DOWNLOAD_DIR}/${SHA_FILE}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-40}"
WAIT_SECONDS="${WAIT_SECONDS:-8}"

BROWSER_UA="${BROWSER_UA:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36}"

mkdir -p "$DOWNLOAD_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

verify_sha512() {
    if [[ ! -s "$SHA_TARGET" || ! -s "$TARGET" ]]; then
        return 1
    fi

    local expected
    expected="$(awk '{print $1; exit}' "$SHA_TARGET")"

    if [[ -z "$expected" ]]; then
        log "Invalid SHA512 file: $SHA_TARGET"
        return 1
    fi

    echo "${expected}  ${TARGET}" | sha512sum -c - >/dev/null
}

download_sha512() {
    log "Downloading SHA512 checksum..."

    wget \
        --tries=10 \
        --timeout=30 \
        --read-timeout=60 \
        --waitretry=5 \
        --user-agent="$BROWSER_UA" \
        --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        --header="Accept-Language: en-US,en;q=0.9" \
        --header="Connection: keep-alive" \
        -O "$SHA_TARGET.tmp" \
        "$SHA_URL"

    mv -f "$SHA_TARGET.tmp" "$SHA_TARGET"
}

download_with_wget_resume() {
    local attempt="$1"

    log "wget attempt ${attempt}/${MAX_ATTEMPTS}"
    log "Target: $TARGET"

    wget \
        --continue \
        --tries=1 \
        --timeout=30 \
        --dns-timeout=30 \
        --connect-timeout=30 \
        --read-timeout=60 \
        --waitretry=5 \
        --user-agent="$BROWSER_UA" \
        --referer="https://calibre-ebook.com/download_linux" \
        --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
        --header="Accept-Language: en-US,en;q=0.9" \
        --header="Connection: keep-alive" \
        --progress=bar:force:noscroll \
        -O "$TARGET" \
        "$URL"
}

download_with_curl_resume() {
    local attempt="$1"

    log "curl fallback attempt ${attempt}/${MAX_ATTEMPTS}"

    curl \
        -fL \
        -C - \
        --retry 0 \
        --connect-timeout 30 \
        --max-time 0 \
        --speed-time 90 \
        --speed-limit 1024 \
        -A "$BROWSER_UA" \
        -e "https://calibre-ebook.com/download_linux" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Connection: keep-alive" \
        -o "$TARGET" \
        "$URL"
}

main() {
    log "Preparing Calibre download"
    log "Version: $VERSION"
    log "Arch:    $ARCH"
    log "URL:     $URL"

    # Prevent two cron/updater runs from downloading the same file at once.
    exec 9>"${DOWNLOAD_DIR}/.${FILE}.lock"
    if ! flock -n 9; then
        log "Another download is already running for $FILE"
        exit 1
    fi

    download_sha512

    if verify_sha512; then
        log "Existing file already verified: $TARGET"
        exit 0
    fi

    log "Starting/resuming Calibre download..."

    for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
        if download_with_wget_resume "$attempt"; then
            if verify_sha512; then
                log "Download completed and SHA512 verified."
                log "OK: $TARGET"
                exit 0
            fi

            log "Download finished but SHA512 verification failed."
            log "Deleting corrupted file and retrying from zero."
            rm -f "$TARGET"
        else
            log "wget failed/interrupted. Will resume after ${WAIT_SECONDS}s."
        fi

        sleep "$WAIT_SECONDS"
    done

    log "wget did not complete successfully after ${MAX_ATTEMPTS} attempts."
    log "Trying curl resume fallback..."

    for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
        if download_with_curl_resume "$attempt"; then
            if verify_sha512; then
                log "Download completed and SHA512 verified with curl fallback."
                log "OK: $TARGET"
                exit 0
            fi

            log "curl finished but SHA512 verification failed."
            log "Deleting corrupted file and retrying from zero."
            rm -f "$TARGET"
        else
            log "curl failed/interrupted. Will resume after ${WAIT_SECONDS}s."
        fi

        sleep "$WAIT_SECONDS"
    done

    log "ERROR: Failed to download verified Calibre tarball: $FILE"
    exit 1
}

main "$@"
