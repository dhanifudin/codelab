#!/usr/bin/env bash
# Push this repo to the VPS and run provision/provision.sh there with sudo.
# Usage: scripts/provision-remote.sh <ssh-host> <site>      (e.g. codelab spi)
# Secrets come from ~/.config/codelab/<site>.env (written by setup-github.sh, mode 600):
# <SITE>_DB_PASSWORD, and for Cloudflare sites CF_CERTBOT_TOKEN (+ optional CERTBOT_EMAIL).
# They travel over ssh stdin, never argv.
set -euo pipefail

HOST=${1:?usage: provision-remote.sh <ssh-host> <site>}
SITE=${2:?site}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}/$SITE.env"
PW_VAR="${SITE^^}_DB_PASSWORD"

db_password=; cf_token=; certbot_email=
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    db_password=$(set -a; . "$ENV_FILE"; printf '%s' "${!PW_VAR:-}")
    # shellcheck source=/dev/null
    cf_token=$(set -a; . "$ENV_FILE"; printf '%s' "${CF_CERTBOT_TOKEN:-}")
    # shellcheck source=/dev/null
    certbot_email=$(set -a; . "$ENV_FILE"; printf '%s' "${CERTBOT_EMAIL:-}")
fi
[ -n "$db_password" ] || echo "note: no $PW_VAR in $ENV_FILE; database user password will not be set" >&2

rsync -az --delete --exclude .git "$ROOT/" "$HOST:codelab/"
# Secrets travel over ssh stdin, one per line, never argv.
printf '%s\n%s\n%s\n' "$db_password" "$cf_token" "$certbot_email" | ssh "$HOST" "
    IFS= read -r $PW_VAR; IFS= read -r CF_CERTBOT_TOKEN; IFS= read -r CERTBOT_EMAIL
    export $PW_VAR CF_CERTBOT_TOKEN CERTBOT_EMAIL
    sudo --preserve-env=$PW_VAR,CF_CERTBOT_TOKEN,CERTBOT_EMAIL bash \"\$HOME/codelab/provision/provision.sh\" '$SITE'
"
