#!/usr/bin/env bash
# Provision one site on the codelab VPS. Idempotent: safe to run repeatedly.
# Usage: sudo SPI_DB_PASSWORD=... provision.sh <site>
set -euo pipefail

SITE=${1:?usage: provision.sh <site>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITE_DIR="$HERE/../sites/$SITE"
[ -f "$SITE_DIR/site.conf" ] || { echo "no such site: $SITE" >&2; exit 1; }

# shellcheck source=lib.sh
source "$HERE/lib.sh"
# shellcheck source=/dev/null
source "$SITE_DIR/site.conf"

require_root
export SITE_DIR HERE
export SITE DOMAIN APP_REPO PHP_VERSION DEPLOY_USER WEB_GROUP BASE KEEP_RELEASES DB_NAME DB_USER POOL_NAME

for step in "$HERE"/[0-9][0-9]-*.sh; do
    log "== $(basename "$step")"
    # shellcheck source=/dev/null
    source "$step"
done
log "done"
