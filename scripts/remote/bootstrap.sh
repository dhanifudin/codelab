#!/usr/bin/env bash
# Runs on the VPS as the deploy user, over ssh: bash -s -- <site>
# Runs the site's production seeder ($SEED_CLASS from /etc/codelab/<site>.conf) against the
# active release. Seeder inputs arrive on stdin as NAME=VALUE lines (never argv); names must
# start with <SITE>_ (e.g. HALOKES_ADMIN_EMAIL) and are exported for the seeder to read via env().
set -euo pipefail

SITE=${1:?site}
# shellcheck source=/dev/null
source "/etc/codelab/$SITE.conf"
: "${SEED_CLASS:?site.conf has no SEED_CLASS}"
PREFIX=${SITE^^}_

while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%%=*}
    [[ "$name" =~ ^${PREFIX}[A-Z0-9_]+$ ]] || { echo "refusing variable name: $name" >&2; exit 1; }
    export "$name=${line#*=}"
done

cd "$BASE/current"
"php$PHP_VERSION" artisan db:seed --class="$SEED_CLASS" --force --no-interaction
