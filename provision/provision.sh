#!/usr/bin/env bash
# Provision one site on the codelab VPS. Idempotent: safe to run repeatedly.
# Usage: sudo SPI_DB_PASSWORD=... provision.sh <site>
set -euo pipefail

SITE=${1:?usage: provision.sh <site>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$HERE/.." && pwd)
SITE_DIR="$ROOT_DIR/sites/$SITE"
[ -f "$SITE_DIR/site.conf" ] || { echo "no such site: $SITE" >&2; exit 1; }

# shellcheck source=lib.sh
source "$HERE/lib.sh"
# shellcheck source=/dev/null
source "$SITE_DIR/site.conf"

require_root
: "${SERVER_NAMES:=$DOMAIN}" "${CERT_NAMES:=$SERVER_NAMES}" "${TENANTS:=}" "${TLS:=none}" "${DISABLE_STOCK_POOL:=0}" "${PHP_EXTENSIONS:=fpm cli common mysql zip mbstring xml curl intl}" "${KIND:=laravel}" "${SERVICE:=}" "${APP_PORT:=}"
export SITE_DIR HERE ROOT_DIR
# Set by 25-tls.sh when a certificate covering the site exists; 30-site.sh picks the HTTPS vhost from it.
TLS_READY=0
export SITE DOMAIN SERVER_NAMES CERT_NAMES TENANTS APP_REPO PHP_VERSION DEPLOY_USER WEB_GROUP BASE KEEP_RELEASES DB_NAME DB_USER POOL_NAME TLS DISABLE_STOCK_POOL PHP_EXTENSIONS KIND SERVICE APP_PORT

for step in "$HERE"/[0-9][0-9]-*.sh; do
    log "== $(basename "$step")"
    # shellcheck source=/dev/null
    source "$step"
done
log "done"
