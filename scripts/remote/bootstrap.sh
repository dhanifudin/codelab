#!/usr/bin/env bash
# Runs on the VPS as the deploy user, over ssh: bash /tmp/bootstrap-site.sh <site> [SeederClass]
# Runs a seeder against the active release: the site's production seeder ($SEED_CLASS from
# /etc/codelab/<site>.conf) or the class given as second argument (for example DemoSeeder).
# Seeder inputs arrive on stdin as NAME=VALUE lines (never argv); names must
# start with <SITE>_ (e.g. HALOKES_ADMIN_EMAIL) and are exported for the seeder to read via env().
set -euo pipefail

SITE=${1:?site}
# shellcheck source=/dev/null
source "/etc/codelab/$SITE.conf"
SEEDER=${2:-${SEED_CLASS:-}}
[ -n "$SEEDER" ] || { echo "no seeder: pass one or set SEED_CLASS in site.conf" >&2; exit 1; }
[[ "$SEEDER" =~ ^[A-Za-z0-9_]+$ ]] || { echo "bad seeder class: $SEEDER" >&2; exit 1; }
PREFIX=${SITE^^}_

while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%%=*}
    [[ "$name" =~ ^${PREFIX}[A-Z0-9_]+$ ]] || { echo "refusing variable name: $name" >&2; exit 1; }
    export "$name=${line#*=}"
done

cd "$BASE/current"
"php$PHP_VERSION" artisan db:seed --class="$SEEDER" --force --no-interaction
