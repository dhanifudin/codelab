#!/usr/bin/env bash
# Push this repo to the VPS and run provision/provision.sh there with sudo.
# Usage: scripts/provision-remote.sh <ssh-host> <site>      (e.g. codelab spi)
# Secrets come from ~/.config/codelab/<site>.env (written by setup-github.sh, mode 600);
# they travel over ssh stdin, never argv.
set -euo pipefail

HOST=${1:?usage: provision-remote.sh <ssh-host> <site>}
SITE=${2:?site}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}/$SITE.env"
PW_VAR="${SITE^^}_DB_PASSWORD"

db_password=
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    db_password=$(set -a; . "$ENV_FILE"; printf '%s' "${!PW_VAR:-}")
fi
[ -n "$db_password" ] || echo "note: no $PW_VAR in $ENV_FILE; database user password will not be set" >&2

rsync -az --delete --exclude .git "$ROOT/" "$HOST:codelab/"
printf '%s\n' "$db_password" | ssh "$HOST" "
    IFS= read -r $PW_VAR; export $PW_VAR
    sudo --preserve-env=$PW_VAR bash \"\$HOME/codelab/provision/provision.sh\" '$SITE'
"
