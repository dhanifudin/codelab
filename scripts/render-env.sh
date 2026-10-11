#!/usr/bin/env bash
# Render sites/<site>/env.template to stdout from <SITE>_* environment variables.
# Fails (without printing secrets) when a required variable is empty.
# Usage: SPI_APP_KEY=... SPI_DB_PASSWORD=... render-env.sh spi > .env
set -euo pipefail

SITE=${1:?usage: render-env.sh <site>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITE_DIR="$HERE/../sites/$SITE"
TEMPLATE="$SITE_DIR/env.template"
[ -f "$TEMPLATE" ] || { echo "no env.template for $SITE" >&2; exit 1; }

# shellcheck source=/dev/null
source "$SITE_DIR/site.conf"
PREFIX=${SITE^^}_

# Optional per-site defaults (derived values, optional variables).
# shellcheck source=/dev/null
[ ! -f "$SITE_DIR/env.defaults.sh" ] || source "$SITE_DIR/env.defaults.sh"

for v in ${ENV_REQUIRED:-}; do
    [ -n "${!v:-}" ] || { echo "required variable $v is empty" >&2; exit 1; }
done
key_var=${PREFIX}APP_KEY
case ${!key_var:-} in base64:*) ;; *) echo "$key_var must look like base64:..." >&2; exit 1 ;; esac

# Explicit variable list so Laravel's own ${APP_NAME} references are left untouched.
vars=$(grep -oE "\\$\\{${PREFIX}[A-Z_]*\\}" "$TEMPLATE" | sort -u | tr '\n' ' ')
for v in $vars; do
    name=${v#\$\{}; name=${name%\}}
    declare -p "$name" >/dev/null 2>&1 || { echo "template variable $name is unset" >&2; exit 1; }
    export "${name?}"
done
envsubst "$vars" <"$TEMPLATE"
