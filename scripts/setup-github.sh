#!/usr/bin/env bash
# One-time (re-runnable) wizard: creates the private GitHub repo, the repo-wide deploy key and the
# secrets for one site. Existing generated values are reused, never regenerated.
#
# Usage: scripts/setup-github.sh <site> [ssh-host-alias]       (e.g. halokes codelab)
# Needs: gh (logged in), ssh, ssh-keygen, openssl.
# Local secret store: ~/.config/codelab/ (mode 700), outside the repo.
#
# Without a tty (e.g. `!` in Claude Code) pass answers as env vars:
#   CONFIRM_FINGERPRINT=SHA256:...   host key fingerprint you verified
#   <SITE>_ADMIN_NAME / _EMAIL       first Super Admin (spi also _USERNAME)
#   CF_CERTBOT_TOKEN                 Cloudflare token for certbot (DNS:Edit on the zone), Cloudflare sites
#   CF_API_TOKEN                     Cloudflare token for scripts/cf-dns.sh, optional here
#   APP_READ_TOKEN                   fine-grained PAT, Contents:read on a private app repo
set -euo pipefail

SITE=${1:?usage: setup-github.sh <site> [ssh-host-alias]}
SSH_ALIAS=${2:-codelab}
REPO=dhanifudin/codelab
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/sites/$SITE/site.conf"
P=${SITE^^}_
STORE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}"
ENV_FILE="$STORE/$SITE.env"
KEY="$STORE/deploy_key"

say()  { printf '\n== %s\n' "$*"; }
ask()  { local p=$1 d=${2:-} a; read -r -p "$p${d:+ [$d]}: " a; printf '%s' "${a:-$d}"; }
asks() { local a; read -rs -p "$1: " a; echo >&2; printf '%s' "$a"; }
rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
tty()  { [ -t 0 ]; }

command -v gh >/dev/null || { echo "gh not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login" >&2; exit 1; }
install -d -m 700 "$STORE"
touch "$ENV_FILE"; chmod 600 "$ENV_FILE"

get() { ( set -a; . "$ENV_FILE"; printf '%s' "${!1:-}" ); }
put() { # put VAR VALUE: replace or append in the local store
    grep -v "^$1=" "$ENV_FILE" >"$ENV_FILE.tmp" || true
    printf '%s=%q\n' "$1" "$2" >>"$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE"
}
# want VAR PROMPT [DEFAULT]: keep stored value, else env var of the same name, else prompt (tty only).
want() {
    local v=$1 cur
    cur=$(get "$v"); [ -z "$cur" ] || return 0
    cur=${!v:-}
    if [ -z "$cur" ]; then
        tty || { echo "set $v in the environment (no tty to ask)" >&2; exit 1; }
        cur=$(ask "$2" "${3:-}")
    fi
    put "$v" "$cur"
}

say "1/6 GitHub repo $REPO (private)"
if gh repo view "$REPO" >/dev/null 2>&1; then
    echo "exists"
else
    gh repo create "$REPO" --private --description "Ops config for sites on the codelab VPS"
fi
git -C "$ROOT" remote get-url origin >/dev/null 2>&1 \
    || git -C "$ROOT" remote add origin "git@github.com:$REPO.git"

say "2/6 Deploy SSH key (one key for all sites)"
if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "codelab-deploy" -f "$KEY"
    echo "generated $KEY"
fi
cp "$KEY.pub" "$ROOT/deploy.pub"
echo "public key written to deploy.pub (commit it; provisioning installs it for the deploy user)"

say "3/6 Host key pinning"
HOSTNAME_RESOLVED=$(ssh -G "$SSH_ALIAS" | awk '/^hostname /{print $2}')
[ -n "$HOSTNAME_RESOLVED" ] || { echo "cannot resolve ssh alias $SSH_ALIAS" >&2; exit 1; }
KNOWN=$(ssh-keyscan -t ed25519 "$HOSTNAME_RESOLVED" 2>/dev/null)
[ -n "$KNOWN" ] || { echo "ssh-keyscan returned nothing for $HOSTNAME_RESOLVED" >&2; exit 1; }
SEEN_FPR=$(printf '%s\n' "$KNOWN" | ssh-keygen -lf - | awk '{print $2}')
echo "Fingerprint seen on the network: $SEEN_FPR"
echo "Compare with the server:  ssh $SSH_ALIAS 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'"
if [ -n "${CONFIRM_FINGERPRINT:-}" ]; then
    [ "$CONFIRM_FINGERPRINT" = "$SEEN_FPR" ] || { echo "fingerprint mismatch" >&2; exit 1; }
else
    tty || { echo "no tty: set CONFIRM_FINGERPRINT=$SEEN_FPR after verifying it" >&2; exit 1; }
    [ "$(ask 'Fingerprints match? (yes/no)' no)" = yes ] || { echo "aborted"; exit 1; }
fi

say "4/6 Generated secrets (kept in $ENV_FILE)"
[ -n "$(get "${P}APP_KEY")" ]     || put "${P}APP_KEY" "base64:$(openssl rand -base64 32)"
[ -n "$(get "${P}DB_PASSWORD")" ] || put "${P}DB_PASSWORD" "$(rand 24)"

say "5/6 First Super Admin"
want "${P}ADMIN_NAME" "Admin name" "Super Admin"
want "${P}ADMIN_EMAIL" "Admin email"
[ "$SITE" != spi ] || want "${P}ADMIN_USERNAME" "Admin username (also NIP)" "admin"
if [ -z "$(get "${P}ADMIN_PASSWORD")" ]; then
    put "${P}ADMIN_PASSWORD" "$(rand 20)"
    echo "generated admin password; read it from $ENV_FILE (${P}ADMIN_PASSWORD) and change it after first login"
fi

if [ "${TLS:-none}" = letsencrypt-cloudflare ]; then
    say "5b/6 Cloudflare tokens (local only; never sent to GitHub)"
    if [ -z "$(get CF_CERTBOT_TOKEN)" ]; then
        t=${CF_CERTBOT_TOKEN:-}
        [ -n "$t" ] || { tty && t=$(asks "Certbot token (DNS:Edit on ${CF_ZONE:-the zone} only)") || true; }
        [ -n "$t" ] || { echo "set CF_CERTBOT_TOKEN (see docs/cloudflare-migration.md)" >&2; exit 1; }
        put CF_CERTBOT_TOKEN "$t"
    fi
    if [ -n "${CF_API_TOKEN:-}" ] && ! grep -q '^CF_API_TOKEN=' "$STORE/cloudflare.env" 2>/dev/null; then
        printf 'CF_API_TOKEN=%q\n' "$CF_API_TOKEN" >>"$STORE/cloudflare.env"; chmod 600 "$STORE/cloudflare.env"
        echo "stored CF_API_TOKEN in $STORE/cloudflare.env"
    fi
fi

say "6/6 Repo secrets on $REPO"
setsec() { printf '%s' "$2" | gh secret set "$1" --repo "$REPO" >/dev/null; echo "set $1"; }
setsec SSH_HOST         "$HOSTNAME_RESOLVED"
setsec SSH_USER         "$DEPLOY_USER"
setsec SSH_PRIVATE_KEY  "$(cat "$KEY")"
setsec SSH_KNOWN_HOSTS  "$KNOWN"
for v in APP_KEY DB_PASSWORD ADMIN_NAME ADMIN_EMAIL ADMIN_PASSWORD; do
    setsec "${P}$v" "$(get "${P}$v")"
done
[ "$SITE" != spi ] || setsec "${P}ADMIN_USERNAME" "$(get "${P}ADMIN_USERNAME")"

if [ "$(gh repo view "$APP_REPO" --json isPrivate -q .isPrivate 2>/dev/null || echo true)" = true ]; then
    if [ -n "${APP_READ_TOKEN:-}" ]; then
        setsec APP_READ_TOKEN "$APP_READ_TOKEN"
    else
        echo "NOTE: $APP_REPO is private. Deploys need secret APP_READ_TOKEN (fine-grained PAT, Contents: read on $APP_REPO):"
        echo "      gh secret set APP_READ_TOKEN --repo $REPO"
    fi
fi

cat <<EOF

Remaining manual step (cannot be automated):
  Create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new
    Resource owner: dhanifudin, Repository access: only $REPO,
    Permissions: Contents = Read and write (needed for repository_dispatch).
  Then store it in the app repo:
    gh secret set CODELAB_DISPATCH_TOKEN --repo $APP_REPO
EOF
