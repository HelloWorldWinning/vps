#!/usr/bin/env bash
set -euo pipefail

ACME_EMAIL="ofwardao@gmail.com"
MANAGER="/usr/local/bin/acme-manager"
OLD_MANAGER="/usr/local/sbin/acme-renew-all.sh"
MAP="/etc/acme-deploy-map.tsv"
LOG="/var/log/acme-manager.log"
CRON_MARKER="# acme-manager managed cron"
CRON_LINE="17 3 * * * $MANAGER --cron >> $LOG 2>&1 $CRON_MARKER"

if [[ "${EUID}" -ne 0 ]]; then
	echo "ERROR: run as root"
	exit 1
fi

mkdir -p /usr/local/bin
mkdir -p /etc/ssl/acme-managed
touch "$LOG"
chmod 600 "$LOG"

cat >"$MANAGER" <<'ACME_MANAGER_EOF'
#!/usr/bin/env bash
set -euo pipefail

ACME_HOME="${ACME_HOME:-/root/.acme.sh}"
ACME_BIN="${ACME_HOME}/acme.sh"
MAP="${ACME_MAP:-/etc/acme-deploy-map.tsv}"
LOG="${ACME_LOG:-/var/log/acme-manager.log}"
SSL_BASE="${SSL_BASE:-/etc/ssl/acme-managed}"

CRON_MARKER="# acme-manager managed cron"
CRON_LINE="17 3 * * * /usr/local/bin/acme-manager --cron >> /var/log/acme-manager.log 2>&1 $CRON_MARKER"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

say() {
    echo -e "$*"
}

die() {
    say "${RED}ERROR:${NC} $*" >&2
    exit 1
}

need_root() {
    [[ "${EUID}" -eq 0 ]] || die "Please run as root."
}

pause() {
    echo ""
    read -r -p "Press Enter to continue..." _
}

ensure_base() {
    mkdir -p "$(dirname "$MAP")"
    mkdir -p "$(dirname "$LOG")"
    mkdir -p "$SSL_BASE"
    touch "$LOG"

    if [[ ! -f "$MAP" ]]; then
        cat > "$MAP" <<'EOF'
# domain	cert_path	key_path	service	mode	challenge_path
EOF
        chmod 600 "$MAP"
    fi
}



ensure_acme() {
    if [[ -x "$ACME_BIN" ]]; then
        return 0
    fi

    local found
    found="$(command -v acme.sh || true)"

    if [[ -n "$found" && -x "$found" ]]; then
        ACME_BIN="$found"
        ACME_HOME="$(dirname "$found")"
        return 0
    fi

    say "${YELLOW}acme.sh not found. Installing now...${NC}"

    if ! command -v curl >/dev/null 2>&1; then
        die "curl is required to install acme.sh. Install curl first: apt install -y curl"
    fi

    curl https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@example.com}"

    if [[ -x "$ACME_BIN" ]]; then
        say "${GREEN}acme.sh installed:${NC} $ACME_BIN"
        return 0
    fi

    found="$(command -v acme.sh || true)"
    if [[ -n "$found" && -x "$found" ]]; then
        ACME_BIN="$found"
        ACME_HOME="$(dirname "$found")"
        say "${GREEN}acme.sh installed:${NC} $ACME_BIN"
        return 0
    fi

    die "acme.sh install failed. Expected: $ACME_BIN"
}


is_comment_or_empty() {
    local x="${1:-}"
    [[ -z "$x" || "$x" =~ ^[[:space:]]*# ]]
}

domain_exists_in_map() {
    local domain="$1"
    [[ -f "$MAP" ]] || return 1
    awk -F '\t' -v d="$domain" '($1 == d) { found=1 } END { exit found ? 0 : 1 }' "$MAP"
}

upsert_domain() {
    local domain="$1"
    local cert_path="$2"
    local key_path="$3"
    local service="$4"
    local mode="$5"
    local challenge_path="$6"

    ensure_base

    local tmp
    tmp="$(mktemp)"

    awk -F '\t' -v d="$domain" 'BEGIN{OFS=FS} $1 != d {print}' "$MAP" > "$tmp" || true
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$domain" "$cert_path" "$key_path" "$service" "$mode" "$challenge_path" >> "$tmp"

    mv "$tmp" "$MAP"
    chmod 600 "$MAP"
}

remove_domain_from_map() {
    local domain="$1"
    ensure_base

    local tmp
    tmp="$(mktemp)"

    awk -F '\t' -v d="$domain" 'BEGIN{OFS=FS} $1 != d {print}' "$MAP" > "$tmp" || true
    mv "$tmp" "$MAP"
    chmod 600 "$MAP"
}

install_cron() {
    need_root

    local tmp
    tmp="$(mktemp)"

    crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" > "$tmp" || true
    echo "$CRON_LINE" >> "$tmp"
    crontab "$tmp"
    rm -f "$tmp"

    say "${GREEN}Cron installed without duplication.${NC}"
    say "  $CRON_LINE"
}

remove_cron() {
    need_root

    local tmp
    tmp="$(mktemp)"

    crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" > "$tmp" || true
    crontab "$tmp"
    rm -f "$tmp"

    say "${GREEN}Managed cron removed.${NC}"
}

show_cron() {
    if crontab -l 2>/dev/null | grep -F "$CRON_MARKER" >/dev/null 2>&1; then
        say "${GREEN}Cron exists:${NC}"
        crontab -l 2>/dev/null | grep -F "$CRON_MARKER" || true
    else
        say "${YELLOW}Cron is not installed.${NC}"
    fi
}

detect_service_default() {
    if systemctl list-unit-files apache2.service >/dev/null 2>&1; then
        echo "apache2"
    elif systemctl list-unit-files nginx.service >/dev/null 2>&1; then
        echo "nginx"
    else
        echo "apache2"
    fi
}

list_map() {
    ensure_base

    local count=0

    say "${CYAN}Registered managed domains:${NC}"

    while IFS=$'\t' read -r domain cert_path key_path service mode challenge_path extra; do
        if is_comment_or_empty "${domain:-}"; then
            continue
        fi

        count=$((count + 1))

        echo ""
        echo "[$count] $domain"
        echo "    cert:    $cert_path"
        echo "    key:     $key_path"
        echo "    service: $service"
        echo "    mode:    $mode"
        echo "    path:    $challenge_path"
    done < "$MAP"

    if [[ "$count" -eq 0 ]]; then
        say "${YELLOW}No domains registered yet.${NC}"
    fi
}

show_acme_list() {
    ensure_acme

    say "${CYAN}acme.sh known certificates:${NC}"
    "$ACME_BIN" --list || true
}

find_acme_domains() {
    ensure_acme

    find "$ACME_HOME" -maxdepth 1 -type d -name "*_ecc" 2>/dev/null \
        | sed 's#/$##' \
        | while read -r dir; do
            local base domain fullchain key
            base="$(basename "$dir")"
            domain="${base%_ecc}"
            fullchain="$dir/fullchain.cer"
            key="$dir/$domain.key"

            if [[ -f "$fullchain" && -f "$key" ]]; then
                echo "$domain"
            fi
        done | sort -u
}

is_valid_cert_file() {
    local cert="$1"

    [[ -f "$cert" ]] || return 1
    openssl x509 -in "$cert" -noout -subject -dates >/dev/null 2>&1
}

import_existing() {
    need_root
    ensure_base
    ensure_acme

    local service
    service="$(detect_service_default)"

    say "${CYAN}Scanning existing acme.sh ECC certificates...${NC}"
    echo ""

    local domains
    domains="$(find_acme_domains || true)"

    if [[ -z "$domains" ]]; then
        say "${YELLOW}No existing valid acme.sh ECC certificate folders found.${NC}"
        say "Check with:"
        say "  $ACME_BIN --list"
        return 0
    fi

    local imported=0
    local skipped=0

    while read -r domain; do
        [[ -n "$domain" ]] || continue

        local src_cert="$ACME_HOME/${domain}_ecc/fullchain.cer"
        local src_key="$ACME_HOME/${domain}_ecc/${domain}.key"

        if ! is_valid_cert_file "$src_cert"; then
            say "${YELLOW}Skipping invalid cert folder:${NC} $domain"
            skipped=$((skipped + 1))
            continue
        fi

        local cert_path="$SSL_BASE/$domain/fullchain.pem"
        local key_path="$SSL_BASE/$domain/privkey.pem"

        say "${GREEN}Importing:${NC} $domain"
        say "  service: $service"
        say "  cert:    $cert_path"
        say "  key:     $key_path"

        upsert_domain "$domain" "$cert_path" "$key_path" "$service" "imported" "-"

        imported=$((imported + 1))
    done <<< "$domains"

    echo ""
    say "${GREEN}Imported/updated:${NC} $imported"
    say "${YELLOW}Skipped:${NC} $skipped"

    if [[ "$imported" -gt 0 ]]; then
        echo ""
        read -r -p "Deploy imported certificates now? [Y/n]: " yn
        yn="${yn:-Y}"

        case "$yn" in
            y|Y|yes|YES)
                deploy_all
                ;;
            *)
                say "${YELLOW}Skipped deploy.${NC}"
                ;;
        esac
    fi
}

deploy_all() {
    need_root
    ensure_base
    ensure_acme

    local count=0
    local failed=0
    local services=""

    say "${CYAN}Deploying registered certificates...${NC}"

    while IFS=$'\t' read -r domain cert_path key_path service mode challenge_path extra; do
        if is_comment_or_empty "${domain:-}"; then
            continue
        fi

        count=$((count + 1))

        mkdir -p "$(dirname "$cert_path")" "$(dirname "$key_path")"

        say ""
        say "${CYAN}Deploying $domain${NC}"
        say "  cert: $cert_path"
        say "  key:  $key_path"

        if "$ACME_BIN" --install-cert -d "$domain" --ecc \
            --fullchain-file "$cert_path" \
            --key-file "$key_path" \
            --reloadcmd "true"; then

            chmod 644 "$cert_path" || true
            chmod 600 "$key_path" || true
            services="$services $service"
            say "${GREEN}OK:${NC} $domain"
        else
            say "${RED}FAILED:${NC} $domain"
            failed=$((failed + 1))
        fi
    done < "$MAP"

    if [[ "$count" -eq 0 ]]; then
        say "${YELLOW}No registered domains. Nothing to deploy.${NC}"
        return 0
    fi

    echo ""

    for svc in $(echo "$services" | tr ' ' '\n' | sort -u); do
        [[ -z "$svc" || "$svc" == "-" ]] && continue

        say "${CYAN}Reloading service:${NC} $svc"

        if systemctl reload "$svc"; then
            say "${GREEN}Reloaded:${NC} $svc"
        else
            say "${YELLOW}Reload failed. Trying restart:${NC} $svc"
            if systemctl restart "$svc"; then
                say "${GREEN}Restarted:${NC} $svc"
            else
                say "${RED}Could not reload/restart:${NC} $svc"
                failed=$((failed + 1))
            fi
        fi
    done

    if [[ "$failed" -gt 0 ]]; then
        say "${RED}Deploy completed with $failed failure(s).${NC}"
        return 1
    fi

    say "${GREEN}Deploy completed successfully.${NC}"
}

renew_all() {
    need_root
    ensure_base
    ensure_acme

    say "${CYAN}Running acme.sh renewal check...${NC}"

    if "$ACME_BIN" --cron --home "$ACME_HOME"; then
        say "${GREEN}acme.sh renewal check completed.${NC}"
    else
        say "${RED}acme.sh renewal check failed.${NC}"
        return 1
    fi

    echo ""
    deploy_all
}

issue_new_interactive() {
    need_root
    ensure_base
    ensure_acme

    local domain service mode webroot cert_path key_path

    echo ""
    read -r -p "Real domain, example gcp.zhulei.eu.org: " domain
    [[ -n "$domain" ]] || die "domain is empty"

    if [[ "$domain" == "example.com" || "$domain" == *.example.com ]]; then
        die "Do not use example.com. Let's Encrypt refuses placeholder domains."
    fi

    service="$(detect_service_default)"
    read -r -p "Service to reload [$service]: " service_in
    service="${service_in:-$service}"

    echo ""
    echo "Challenge mode:"
    echo "  1) standalone, port 80 must be free/reachable"
    echo "  2) webroot, Apache/Nginx serves /.well-known/acme-challenge/"
    echo ""
    read -r -p "Choose mode [1]: " mode_choice
    mode_choice="${mode_choice:-1}"

    case "$mode_choice" in
        1)
            mode="standalone"
            webroot="-"
            ;;
        2)
            mode="webroot"
            read -r -p "Webroot path [/var/www/html]: " webroot
            webroot="${webroot:-/var/www/html}"
            ;;
        *)
            die "bad choice"
            ;;
    esac

    cert_path="$SSL_BASE/$domain/fullchain.pem"
    key_path="$SSL_BASE/$domain/privkey.pem"

    echo ""
    say "${CYAN}Ready to issue:${NC}"
    echo "  domain:  $domain"
    echo "  service: $service"
    echo "  mode:    $mode"
    echo "  cert:    $cert_path"
    echo "  key:     $key_path"
    echo ""

    read -r -p "Continue? [y/N]: " yn
    case "$yn" in
        y|Y|yes|YES) ;;
        *) say "${YELLOW}Cancelled.${NC}"; return 0 ;;
    esac

    if [[ "$mode" == "standalone" ]]; then
        "$ACME_BIN" --issue -d "$domain" --standalone --keylength ec-256
    else
        "$ACME_BIN" --issue -d "$domain" -w "$webroot" --keylength ec-256
    fi

    upsert_domain "$domain" "$cert_path" "$key_path" "$service" "$mode" "$webroot"
    deploy_all
}

register_manual_interactive() {
    need_root
    ensure_base

    local domain service mode webroot cert_path key_path

    echo ""
    read -r -p "Domain already known by acme.sh: " domain
    [[ -n "$domain" ]] || die "domain is empty"

    service="$(detect_service_default)"
    read -r -p "Service to reload [$service]: " service_in
    service="${service_in:-$service}"

    read -r -p "Mode label [imported]: " mode
    mode="${mode:-imported}"

    read -r -p "Challenge path [-]: " webroot
    webroot="${webroot:--}"

    read -r -p "Cert destination [$SSL_BASE/$domain/fullchain.pem]: " cert_path
    cert_path="${cert_path:-$SSL_BASE/$domain/fullchain.pem}"

    read -r -p "Key destination [$SSL_BASE/$domain/privkey.pem]: " key_path
    key_path="${key_path:-$SSL_BASE/$domain/privkey.pem}"

    upsert_domain "$domain" "$cert_path" "$key_path" "$service" "$mode" "$webroot"

    say "${GREEN}Registered/updated:${NC} $domain"

    read -r -p "Deploy now? [Y/n]: " yn
    yn="${yn:-Y}"

    case "$yn" in
        y|Y|yes|YES) deploy_all ;;
        *) say "${YELLOW}Skipped deploy.${NC}" ;;
    esac
}

remove_interactive() {
    ensure_base
    list_map

    echo ""
    read -r -p "Domain to remove from manager registry: " domain
    [[ -n "$domain" ]] || die "domain is empty"

    remove_domain_from_map "$domain"
    say "${GREEN}Removed from registry:${NC} $domain"
    say "${YELLOW}Note:${NC} this did not delete files from /root/.acme.sh or /etc/ssl."
}

status_all() {
    ensure_base

    say "${CYAN}ACME Manager Status${NC}"
    echo "Manager:   /usr/local/bin/acme-manager"
    echo "ACME_HOME: $ACME_HOME"
    echo "ACME_BIN:  $ACME_BIN"
    echo "Registry:  $MAP"
    echo "SSL base:  $SSL_BASE"
    echo "Log:       $LOG"
    echo ""

    if [[ -x "$ACME_BIN" ]]; then
        say "${GREEN}acme.sh exists.${NC}"
    else
        say "${RED}acme.sh missing.${NC}"
    fi

    echo ""
    show_cron

    echo ""
    list_map

    echo ""
    say "${CYAN}Installed certificate file status:${NC}"

    local count=0

    while IFS=$'\t' read -r domain cert_path key_path service mode challenge_path extra; do
        if is_comment_or_empty "${domain:-}"; then
            continue
        fi

        count=$((count + 1))
        echo ""
        echo "domain: $domain"

        if [[ -f "$cert_path" ]]; then
            echo "cert:   $cert_path"
            openssl x509 -in "$cert_path" -noout -subject -issuer -dates 2>/dev/null || true
        else
            echo "cert:   missing: $cert_path"
        fi

        if [[ -f "$key_path" ]]; then
            echo "key:    exists: $key_path"
        else
            echo "key:    missing: $key_path"
        fi
    done < "$MAP"

    if [[ "$count" -eq 0 ]]; then
        say "${YELLOW}No installed managed certs yet.${NC}"
    fi
}

clean_invalid_example_folders() {
    need_root
    ensure_acme

    echo ""
    say "${YELLOW}This removes failed placeholder acme.sh folders only:${NC}"
    echo "  /root/.acme.sh/example.com_ecc"
    echo "  /root/.acme.sh/cloud.example.com_ecc"
    echo ""

    read -r -p "Remove these if they exist? [y/N]: " yn

    case "$yn" in
        y|Y|yes|YES)
            rm -rf "$ACME_HOME/example.com_ecc" "$ACME_HOME/cloud.example.com_ecc"
            say "${GREEN}Removed placeholder failed folders if present.${NC}"
            ;;
        *)
            say "${YELLOW}Cancelled.${NC}"
            ;;
    esac
}

safe_default() {
    need_root
    ensure_base
    ensure_acme || true

    say "${CYAN}Safe default mode${NC}"
    echo ""

    if crontab -l 2>/dev/null | grep -F "$CRON_MARKER" >/dev/null 2>&1; then
        say "${GREEN}Cron already exists. No duplicate added.${NC}"
    else
        say "${YELLOW}Cron missing. Installing...${NC}"
        install_cron
    fi

    echo ""
    status_all
}

main_menu() {
    ensure_base

    while true; do
        clear || true

        say "${CYAN}========================================${NC}"
        say "${CYAN}        ACME TLS Interactive Manager     ${NC}"
        say "${CYAN}========================================${NC}"
        echo ""
        echo "1) Safe check/install cron"
        echo "2) Auto-import existing valid acme.sh certs"
        echo "3) Show status"
        echo "4) List managed domains"
        echo "5) Show acme.sh certificate list"
        echo "6) Renew now, then deploy"
        echo "7) Deploy only"
        echo "8) Issue a new real Let's Encrypt cert"
        echo "9) Register one existing acme.sh domain manually"
        echo "10) Remove domain from manager registry"
        echo "11) Install cron without duplication"
        echo "12) Remove managed cron"
        echo "13) Clean failed example.com placeholder folders"
        echo "0) Exit"
        echo ""
     #  echo "No input in 10 seconds = safe check/install cron"
        echo ""

        local choice=""
     #  read -r -t 10 -p "Choose: " choice || choice="1"
        read -r  -p "Choose: " choice || choice="1"
        choice="${choice:-1}"

        case "$choice" in
            1) safe_default; pause ;;
            2) import_existing; pause ;;
            3) status_all; pause ;;
            4) list_map; pause ;;
            5) show_acme_list; pause ;;
            6) renew_all; pause ;;
            7) deploy_all; pause ;;
            8) issue_new_interactive; pause ;;
            9) register_manual_interactive; pause ;;
            10) remove_interactive; pause ;;
            11) install_cron; pause ;;
            12) remove_cron; pause ;;
            13) clean_invalid_example_folders; pause ;;
            0) exit 0 ;;
            *) say "${RED}Bad choice.${NC}"; pause ;;
        esac
    done
}

case "${1:-}" in
    --cron)
        renew_all
        ;;
    *)
        main_menu
        ;;
esac
ACME_MANAGER_EOF

chmod +x "$MANAGER"

if [[ ! -f "$MAP" ]]; then
	cat >"$MAP" <<'EOF'
# domain	cert_path	key_path	service	mode	challenge_path
EOF
	chmod 600 "$MAP"
fi

tmp_cron="$(mktemp)"
crontab -l 2>/dev/null | grep -vF "# acme-renew-all managed cron" | grep -vF "$CRON_MARKER" >"$tmp_cron" || true
echo "$CRON_LINE" >>"$tmp_cron"
crontab "$tmp_cron"
rm -f "$tmp_cron"

echo ""
echo "Installed interactive ACME manager:"
echo "  $MANAGER"
echo ""
echo "Run:"
echo "  sudo acme-manager"
echo ""
echo "Cron installed without duplication:"
echo "  $CRON_LINE"
echo ""
echo "Old manager remains here if it exists:"
echo "  $OLD_MANAGER"
echo ""
echo "Recommended next action:"
echo "  sudo acme-manager"
echo "Then choose:"
echo "  2) Auto-import existing valid acme.sh certs"
echo ""
