#!/usr/bin/env bash
# One-time (re-runnable) wizard: creates the private GitHub repo, a deploy key and the
# repo secrets for the spi site. Existing generated values are reused, never regenerated.
#
# Usage: scripts/setup-github.sh [ssh-host-alias]     default alias: codelab
# Needs: gh (logged in), ssh, ssh-keygen, openssl.
# Local secret store: ~/.config/codelab/ (mode 700), outside the repo.
set -euo pipefail

SSH_ALIAS=${1:-codelab}
REPO=dhanifudin/codelab
SITE=spi
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STORE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}"
ENV_FILE="$STORE/$SITE.env"
KEY="$STORE/deploy_$SITE"

say()  { printf '\n== %s\n' "$*"; }
ask()  { local p=$1 d=${2:-} a; read -r -p "$p${d:+ [$d]}: " a; printf '%s' "${a:-$d}"; }
rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

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

say "1/6 GitHub repo $REPO (private)"
if gh repo view "$REPO" >/dev/null 2>&1; then
    echo "exists"
else
    gh repo create "$REPO" --private --description "Ops config for sites on the codelab VPS"
fi
git -C "$ROOT" remote get-url origin >/dev/null 2>&1 \
    || git -C "$ROOT" remote add origin "git@github.com:$REPO.git"

say "2/6 Deploy SSH key"
if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "codelab-deploy-$SITE" -f "$KEY"
    echo "generated $KEY"
fi
cp "$KEY.pub" "$ROOT/sites/$SITE/deploy.pub"
echo "public key written to sites/$SITE/deploy.pub (commit it; provisioning installs it for the deploy user)"

say "3/6 Host key pinning"
HOSTNAME_RESOLVED=$(ssh -G "$SSH_ALIAS" | awk '/^hostname /{print $2}')
[ -n "$HOSTNAME_RESOLVED" ] || { echo "cannot resolve ssh alias $SSH_ALIAS" >&2; exit 1; }
KNOWN=$(ssh-keyscan -t ed25519 "$HOSTNAME_RESOLVED" 2>/dev/null)
[ -n "$KNOWN" ] || { echo "ssh-keyscan returned nothing for $HOSTNAME_RESOLVED" >&2; exit 1; }
echo "Fingerprint seen on the network:"
printf '%s\n' "$KNOWN" | ssh-keygen -lf -
echo "Compare with the server:  ssh $SSH_ALIAS 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'"
# Non-interactive (e.g. run via `!` in Claude Code, no tty): pass the verified fingerprint.
#   CONFIRM_FINGERPRINT=SHA256:... scripts/setup-github.sh codelab
SEEN_FPR=$(printf '%s\n' "$KNOWN" | ssh-keygen -lf - | awk '{print $2}')
if [ -n "${CONFIRM_FINGERPRINT:-}" ]; then
    [ "$CONFIRM_FINGERPRINT" = "$SEEN_FPR" ] || { echo "fingerprint mismatch: got $SEEN_FPR" >&2; exit 1; }
else
    [ -t 0 ] || { echo "no tty: set CONFIRM_FINGERPRINT=$SEEN_FPR after verifying it" >&2; exit 1; }
    [ "$(ask 'Fingerprints match? (yes/no)' no)" = yes ] || { echo "aborted"; exit 1; }
fi

say "4/6 Generated secrets (kept in $ENV_FILE)"
[ -n "$(get SPI_APP_KEY)" ]     || put SPI_APP_KEY "base64:$(openssl rand -base64 32)"
[ -n "$(get SPI_DB_PASSWORD)" ] || put SPI_DB_PASSWORD "$(rand 24)"

say "5/6 Super Admin for the app"
# Preset via env (SPI_ADMIN_NAME/EMAIL/USERNAME) to skip prompts.
[ -n "$(get SPI_ADMIN_NAME)" ]     || put SPI_ADMIN_NAME "${SPI_ADMIN_NAME:-$(ask 'Admin name' 'Super Admin')}"
[ -n "$(get SPI_ADMIN_EMAIL)" ]    || put SPI_ADMIN_EMAIL "${SPI_ADMIN_EMAIL:-$(ask 'Admin email')}"
[ -n "$(get SPI_ADMIN_USERNAME)" ] || put SPI_ADMIN_USERNAME "${SPI_ADMIN_USERNAME:-$(ask 'Admin username (also NIP)' 'admin')}"
if [ -z "$(get SPI_ADMIN_PASSWORD)" ]; then
    put SPI_ADMIN_PASSWORD "$(rand 20)"
    echo "generated admin password; read it from $ENV_FILE (SPI_ADMIN_PASSWORD) and change it after first login"
fi

say "6/6 Repo secrets on $REPO"
setsec() { printf '%s' "$2" | gh secret set "$1" --repo "$REPO" >/dev/null; echo "set $1"; }
setsec SSH_HOST         "$HOSTNAME_RESOLVED"
setsec SSH_USER         "deploy"
setsec SSH_PRIVATE_KEY  "$(cat "$KEY")"
setsec SSH_KNOWN_HOSTS  "$KNOWN"
for v in SPI_APP_KEY SPI_DB_PASSWORD SPI_ADMIN_NAME SPI_ADMIN_EMAIL SPI_ADMIN_USERNAME SPI_ADMIN_PASSWORD; do
    setsec "$v" "$(get "$v")"
done
echo "Optional secrets (set later with: gh secret set NAME --repo $REPO):"
echo "  SPI_MAIL_HOST SPI_MAIL_PORT SPI_MAIL_USERNAME SPI_MAIL_PASSWORD SPI_MAIL_FROM"
echo "  SPI_NOCAPTCHA_SECRET SPI_NOCAPTCHA_SITEKEY"
echo "Optional variable after TLS cutover:  gh variable set SPI_APP_URL --body https://spi.polinema.ac.id --repo $REPO"

cat <<EOF

Remaining manual step (cannot be automated):
  Create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new
    Resource owner: dhanifudin, Repository access: only dhanifudin/codelab,
    Permissions: Contents = Read and write (needed for repository_dispatch).
  Then store it in the app repo:
    gh secret set CODELAB_DISPATCH_TOKEN --repo dhanifudin/spi.polinema.ac.id
EOF
