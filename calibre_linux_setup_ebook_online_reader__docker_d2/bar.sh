cleanup_downloads() {
    local version="$1"
    local arch="${2:-x86_64}"

    local file="calibre-${version}-${arch}.txz"
    local download_dir="${BUILD_CONTEXT}/downloads"

    echo "Cleaning download files for Calibre ${version}..."

    rm -f "${download_dir}/${file}"
    rm -f "${download_dir}/${file}.sha512"
    rm -f "${download_dir}/.${file}.lock"

    # Remove downloads directory only if empty.
    rmdir "${download_dir}" 2>/dev/null || true
}
