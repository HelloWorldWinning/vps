#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  outline_authentiksetup.sh
#
#  One-shot installer for:
#    - Outline (wiki)
#    - Authentik (OIDC provider)
#    - HTTPS Portal (Let's Encrypt reverse proxy)
#
#  Notes / fixes:
#    - Starts HTTPS-Portal in Let's Encrypt **staging** first to avoid
#      rate limit crashes; you can later promote to production.
#    - When OIDC values are added, **force-recreate** Outline so env changes
#      actually apply.
#    - Opens ports 80/443 if UFW is active.
#    - Uses Authentik's current stable image tag by default.
###############################################################################

if [[ "${EUID}" -ne 0 ]]; then
	echo "Please run this script as root (or with sudo)."
	exit 1
fi

read -rp "Enter Outline domain (e.g. outline.example.com): " OUTLINE_DOMAIN
read -rp "Enter Authentik domain (e.g. auth.example.com): " AUTHENTIK_DOMAIN

# Start with Let's Encrypt staging to dodge rate limits while setting up.
# You can later promote to production with the printed commands at the end.
LE_STAGE="${LE_STAGE:-staging}" # staging | production

# Authentik image tag (stable release). You can override via env if desired.
AUTHENTIK_TAG="${AUTHENTIK_TAG:-2025.10.1}"

BASE_DIR="/data/outline_d"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

echo "Using base directory: ${BASE_DIR}"
mkdir -p "${BASE_DIR}"

###############################################################################
# Install Docker & Docker Compose plugin if missing
###############################################################################

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker not found, installing (Debian/Ubuntu-style)..."
	apt-get update
	apt-get install -y ca-certificates curl gnupg lsb-release

	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" |
		gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	chmod a+r /etc/apt/keyrings/docker.gpg

	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
$(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list

	apt-get update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! docker compose version >/dev/null 2>&1; then
	echo "Docker Compose v2 plugin not found. Please install it manually and re-run."
	exit 1
fi

# Install openssl for secret generation
if ! command -v openssl >/dev/null 2>&1; then
	echo "Installing openssl..."
	apt-get update
	apt-get install -y openssl
fi

# If UFW is active, open 80/443
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
	echo "UFW is active; opening ports 80 and 443..."
	ufw allow 80/tcp || true
	ufw allow 443/tcp || true
fi

###############################################################################
# Generate secrets/passwords
###############################################################################

OUTLINE_SECRET_KEY="$(openssl rand -hex 32)"
OUTLINE_UTILS_SECRET="$(openssl rand -hex 32)"
OUTLINE_DB_PASS="$(openssl rand -base64 36 | tr -d '\n' | cut -c1-32)"

AUTHENTIK_PG_PASS="$(openssl rand -base64 36 | tr -d '\n' | cut -c1-32)"
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')"

echo "Generated secrets and DB passwords."

###############################################################################
# Create directory structure
###############################################################################

# Outline
OUTLINE_DIR="${BASE_DIR}/outline"
mkdir -p "${OUTLINE_DIR}"/{storage-data,postgres-data,redis-data}

cat >"${OUTLINE_DIR}/redis.conf" <<'EOF'
save 60 1
loglevel warning
# Ensure Redis saves RDB snapshots to the mounted data dir
dir /data
EOF

# Authentik
AUTHENTIK_DIR="${BASE_DIR}/authentik"
mkdir -p "${AUTHENTIK_DIR}"/{postgres-data,redis-data,media,custom-templates,certs}

# HTTPS portal
HTTPS_PORTAL_DIR="${BASE_DIR}/https-portal"
mkdir -p "${HTTPS_PORTAL_DIR}/data"

###############################################################################
# Fix permissions for Redis data directories (avoid MISCONF RDB errors)
###############################################################################

echo "Fixing permissions on Redis data directories so Redis can persist RDB..."
docker run --rm -v "${AUTHENTIK_DIR}/redis-data:/data" redis chown -R redis:redis /data || true
docker run --rm -v "${OUTLINE_DIR}/redis-data:/data" redis chown -R redis:redis /data || true

###############################################################################
# Authentik .env
###############################################################################

AUTHENTIK_ENV_FILE="${AUTHENTIK_DIR}/.env"

cat >"${AUTHENTIK_ENV_FILE}" <<EOF
# Authentik core secrets
PG_PASS=${AUTHENTIK_PG_PASS}
PG_USER=authentik
PG_DB=authentik

AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_ERROR_REPORTING__ENABLED=true

# External URL & cookie domain (helps behind reverse proxies)
AUTHENTIK_HOST=https://${AUTHENTIK_DOMAIN}
AUTHENTIK_COOKIE_DOMAIN=.${AUTHENTIK_DOMAIN}

# Email "from" address (optional)
AUTHENTIK_EMAIL__FROM=auth@${AUTHENTIK_DOMAIN}
EOF

chmod 600 "${AUTHENTIK_ENV_FILE}"

###############################################################################
# Outline docker.env (initial, OIDC placeholders empty)
###############################################################################

OUTLINE_ENV_FILE="${OUTLINE_DIR}/docker.env"

cat >"${OUTLINE_ENV_FILE}" <<EOF
# ===================== Outline required settings ======================

NODE_ENV=production
SECRET_KEY=${OUTLINE_SECRET_KEY}
UTILS_SECRET=${OUTLINE_UTILS_SECRET}

# Database connection (to the postgres service in docker-compose)
DATABASE_URL=postgres://outline:${OUTLINE_DB_PASS}@postgres:5432/outline

# Postgres in this stack is non-SSL; disable SSL in client
PGSSLMODE=disable

# Redis connection (to the redis service in docker-compose)
REDIS_URL=redis://redis:6379

# Public URL of Outline
URL=https://${OUTLINE_DOMAIN}
PORT=3000

# Trust reverse proxy headers & force HTTPS
TRUST_PROXY=true
FORCE_HTTPS=true

# Local file storage
FILE_STORAGE=local
FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data

# ===================== OIDC via Authentik =============================
# Will be filled after you create the Outline application in Authentik.

OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=

OIDC_AUTH_URI=https://${AUTHENTIK_DOMAIN}/application/o/authorize/
OIDC_TOKEN_URI=https://${AUTHENTIK_DOMAIN}/application/o/token/
OIDC_USERINFO_URI=https://${AUTHENTIK_DOMAIN}/application/o/userinfo/

# Replace YOUR_OUTLINE_APP_SLUG later in this script
OIDC_LOGOUT_URI=https://${AUTHENTIK_DOMAIN}/application/o/YOUR_OUTLINE_APP_SLUG/end-session/

OIDC_USERNAME_CLAIM=preferred_username
OIDC_DISPLAY_NAME=authentik
OIDC_SCOPES=openid profile email
EOF

chmod 600 "${OUTLINE_ENV_FILE}"

###############################################################################
# docker-compose.yml (stage 1: only Authentik behind HTTPS, STAGING certs)
###############################################################################

cat >"${COMPOSE_FILE}" <<EOF
services:
  # ===================== Outline stack =====================
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: "outline"
      POSTGRES_PASSWORD: "${OUTLINE_DB_PASS}"
      POSTGRES_DB: "outline"
    volumes:
      - ./outline/postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d outline -U outline"]
      interval: 30s
      timeout: 20s
      retries: 5

  redis:
    image: redis:alpine
    restart: unless-stopped
    command: ["redis-server", "/redis.conf"]
    volumes:
      - ./outline/redis.conf:/redis.conf
      - ./outline/redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 30s
      retries: 5

  outline:
    image: outlinewiki/outline:latest
    restart: unless-stopped
    env_file:
      - ./outline/docker.env
    expose:
      - "3000"
    volumes:
      - ./outline/storage-data:/var/lib/outline/data
    depends_on:
      - postgres
      - redis

  # ===================== Authentik stack ===================
  auth-postgresql:
    image: postgres:16-alpine
    restart: unless-stopped
    env_file:
      - ./authentik/.env
    environment:
      POSTGRES_PASSWORD: "${AUTHENTIK_PG_PASS}"
      POSTGRES_USER: "authentik"
      POSTGRES_DB: "authentik"
    volumes:
      - ./authentik/postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d authentik -U authentik"]
      start_period: 20s
      interval: 30s
      retries: 10
      timeout: 5s

  auth-redis:
    image: redis:alpine
    command: --save 60 1 --loglevel warning
    restart: unless-stopped
    volumes:
      - ./authentik/redis-data:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
      start_period: 20s
      interval: 30s
      retries: 10
      timeout: 3s

  authentik-server:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG}
    restart: unless-stopped
    command: server
    env_file:
      - ./authentik/.env
    environment:
      AUTHENTIK_REDIS__HOST: auth-redis
      AUTHENTIK_POSTGRESQL__HOST: auth-postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: "${AUTHENTIK_PG_PASS}"
    volumes:
      - ./authentik/media:/media
      - ./authentik/custom-templates:/templates
    depends_on:
      auth-postgresql:
        condition: service_healthy
      auth-redis:
        condition: service_healthy
    expose:
      - "9000"

  authentik-worker:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG}
    restart: unless-stopped
    command: worker
    env_file:
      - ./authentik/.env
    environment:
      AUTHENTIK_REDIS__HOST: auth-redis
      AUTHENTIK_POSTGRESQL__HOST: auth-postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: "${AUTHENTIK_PG_PASS}"
    user: root
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./authentik/media:/media
      - ./authentik/certs:/certs
      - ./authentik/custom-templates:/templates
    depends_on:
      auth-postgresql:
        condition: service_healthy
      auth-redis:
        condition: service_healthy

  # ===================== HTTPS reverse proxy ===================
  https-portal:
    image: steveltn/https-portal:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - authentik-server
      - outline
    volumes:
      - ./https-portal/data:/var/lib/https-portal
    environment:
      # FIRST STAGE: only Authentik exposed, Outline added later
      DOMAINS: "${AUTHENTIK_DOMAIN} -> http://authentik-server:9000"
      STAGE: "${LE_STAGE}"         # staging first; promote to production later
      WEBSOCKET: "true"
      CLIENT_MAX_BODY_SIZE: "0"
EOF

chmod 644 "${COMPOSE_FILE}"

###############################################################################
# Start stack (first stage)
###############################################################################

cd "${BASE_DIR}"
echo "Starting containers (first stage: Authentik + Outline + DBs + proxy @ ${LE_STAGE})..."
docker compose up -d

cat <<'MSG'

===============================================================================
Phase 1 complete.

Open Authentik admin in your browser (certificate may be untrusted if STAGING):

   https://AUTH_DOMAIN_HERE

If needed, set the admin password:
   docker compose exec authentik-server ak changepassword akadmin

Complete the initial setup wizard (admin user, etc).

Then create an OAuth2/OpenID Connect provider + application for Outline:

   Provider type: OAuth2/OpenID Connect
   Strict redirect URI:
       https://OUTLINE_DOMAIN_HERE/auth/oidc.callback
   Subject mode:
       Based on the User's username

Record:
   - Client ID
   - Client Secret
   - Application slug (used for logout URL)

When you have these values ready, return here.
===============================================================================
MSG

# Replace placeholders in the message just printed
printf "\n(Replace AUTH_DOMAIN_HERE with %s and OUTLINE_DOMAIN_HERE with %s in the instructions above.)\n\n" "$AUTHENTIK_DOMAIN" "$OUTLINE_DOMAIN"

read -rp "Press Enter once the Outline OIDC application is created in Authentik..." _

###############################################################################
# Ask user for OIDC values from Authentik
###############################################################################

read -rp "Enter OIDC Client ID from Authentik: " OIDC_CLIENT_ID
read -rp "Enter OIDC Client Secret from Authentik: " OIDC_CLIENT_SECRET
read -rp "Enter Authentik application slug for Outline (e.g. outline): " OIDC_APP_SLUG

###############################################################################
# Rewrite Outline docker.env with OIDC config filled in (keeping PGSSLMODE)
###############################################################################

cat >"${OUTLINE_ENV_FILE}" <<EOF
# ===================== Outline required settings ======================

NODE_ENV=production
SECRET_KEY=${OUTLINE_SECRET_KEY}
UTILS_SECRET=${OUTLINE_UTILS_SECRET}

# Database connection (to the postgres service in docker-compose)
DATABASE_URL=postgres://outline:${OUTLINE_DB_PASS}@postgres:5432/outline

# Postgres in this stack is non-SSL; disable SSL in client
PGSSLMODE=disable

# Redis connection (to the redis service in docker-compose)
REDIS_URL=redis://redis:6379

# Public URL of Outline
URL=https://${OUTLINE_DOMAIN}
PORT=3000

# Trust reverse proxy headers & force HTTPS
TRUST_PROXY=true
FORCE_HTTPS=true

# Local file storage
FILE_STORAGE=local
FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data

# ===================== OIDC via Authentik =============================

OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}

OIDC_AUTH_URI=https://${AUTHENTIK_DOMAIN}/application/o/authorize/
OIDC_TOKEN_URI=https://${AUTHENTIK_DOMAIN}/application/o/token/
OIDC_USERINFO_URI=https://${AUTHENTIK_DOMAIN}/application/o/userinfo/
OIDC_LOGOUT_URI=https://${AUTHENTIK_DOMAIN}/application/o/${OIDC_APP_SLUG}/end-session/

OIDC_USERNAME_CLAIM=preferred_username
OIDC_DISPLAY_NAME=authentik
OIDC_SCOPES=openid profile email
EOF

chmod 600 "${OUTLINE_ENV_FILE}"

echo "Recreating Outline so the updated env takes effect..."
docker compose up -d --no-deps --force-recreate outline

###############################################################################
# Update https-portal DOMAINS to expose both Authentik and Outline
###############################################################################

DOMAINS_SINGLE="${AUTHENTIK_DOMAIN} -> http://authentik-server:9000"
DOMAINS_DUAL="${OUTLINE_DOMAIN} -> http://outline:3000, ${AUTHENTIK_DOMAIN} -> http://authentik-server:9000"

# Replace the DOMAINS line safely
sed -i "s|DOMAINS: \"${DOMAINS_SINGLE}\"|DOMAINS: \"${DOMAINS_DUAL}\"|" "${COMPOSE_FILE}"

echo "Updated https-portal DOMAINS to include Outline. Restarting https-portal..."
docker compose up -d https-portal

###############################################################################
# Done
###############################################################################

cat <<EOF

===============================================================================
Setup complete.

Services:

- Authentik:  https://${AUTHENTIK_DOMAIN}
- Outline:    https://${OUTLINE_DOMAIN}

Data & config layout (for backup/restore):

- ${BASE_DIR}/outline/       -> Outline data, env, postgres, redis
- ${BASE_DIR}/authentik/     -> Authentik data, env, media, certs, templates
- ${BASE_DIR}/https-portal/  -> HTTPS-portal certs/data

Useful commands:

  cd ${BASE_DIR}
  docker compose ps
  docker compose logs --tail=80 outline authentik-server https-portal auth-redis redis auth-postgresql

TLS notes:
- We started with Let's Encrypt STAGE="${LE_STAGE}".
- If it's currently 'staging', promote to production when ready:

    sed -i 's/STAGE: "staging"/STAGE: "production"/' ${COMPOSE_FILE}
    docker compose up -d https-portal

  If you recently hit rate limits, wait until the retry-after time shown by
  https-portal logs before switching back to production.

Other notes:
- Outline connects to Postgres without SSL (PGSSLMODE=disable). If you later
  enable SSL on Postgres, remove or adjust PGSSLMODE accordingly.
- Redis data directories are chowned to the redis user to avoid MISCONF
  snapshotting errors.
- Authentik is pinned to tag ${AUTHENTIK_TAG} by default. You can override the
  AUTHENTIK_TAG environment variable before running this script to use a
  different version.

Enjoy your Outline + Authentik setup!
===============================================================================
EOF
