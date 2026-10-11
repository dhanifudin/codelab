#!/usr/bin/env bash
# Runs on the VPS as the deploy user, piped over ssh: bash -s -- <site> <sha>
# Expects the release already rsynced to $BASE/releases/<sha> and the rendered
# .env uploaded to $BASE/shared/.env. Safe to re-run for the same sha.
set -euo pipefail

SITE=${1:?site}
SHA=${2:?sha}
[[ "$SHA" =~ ^[0-9a-f]{7,40}$ ]] || { echo "bad sha" >&2; exit 1; }

# shellcheck source=/dev/null
source "/etc/codelab/$SITE.conf"
REL="$BASE/releases/$SHA"
SHARED="$BASE/shared"
PHP="php$PHP_VERSION"

[ -d "$REL" ] || { echo "release $REL missing" >&2; exit 1; }
[ -s "$SHARED/.env" ] || { echo "$SHARED/.env missing" >&2; exit 1; }
chmod 600 "$SHARED/.env"

# 1. Persistent paths: seed once from the release (committed samples), then link.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ ! -e "$SHARED/$path" ]; then
        mkdir -p "$(dirname "$SHARED/$path")"
        if [ -d "$REL/$path" ] && [ ! -L "$REL/$path" ]; then
            cp -a "$REL/$path" "$SHARED/$path"
        else
            mkdir -p "$SHARED/$path"
        fi
    fi
    rm -rf "${REL:?}/$path"
    mkdir -p "$(dirname "$REL/$path")"
    ln -s "$SHARED/$path" "$REL/$path"
done <"/etc/codelab/$SITE.shared-paths"

# Laravel needs these under storage/.
mkdir -p "$SHARED"/storage/{app/public,framework/{cache/data,sessions,views},logs}
# Public disk URL: /storage -> shared storage (stable across releases).
rm -rf "$REL/public/storage"
ln -s "$SHARED/storage/app/public" "$REL/public/storage"
ln -sfn "$SHARED/.env" "$REL/.env"

# 2. Writable cache dir inside the release.
mkdir -p "$REL/bootstrap/cache"
chmod 775 "$REL/bootstrap/cache"
chgrp "$WEB_GROUP" "$REL/bootstrap/cache" 2>/dev/null || true

# 3. Migrate + warm caches (before the switch; old release keeps serving).
cd "$REL"
"$PHP" artisan config:clear
"$PHP" artisan migrate --force --no-interaction
"$PHP" artisan config:cache
"$PHP" artisan route:cache
"$PHP" artisan view:cache

# 4. Atomic switch.
PREVIOUS=$(readlink "$BASE/current" 2>/dev/null || true)
ln -sfn "releases/$SHA" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"
sudo -n /usr/bin/systemctl reload "php$PHP_VERSION-fpm"
echo "activated $SHA (previous: ${PREVIOUS:-none})"

# 5. Prune: keep the newest KEEP_RELEASES (never the active one).
active=$(basename "$(readlink "$BASE/current")")
i=0
for d in $(ls -1t "$BASE/releases"); do
    i=$((i + 1))
    if [ "$i" -gt "$KEEP_RELEASES" ] && [ "$d" != "$active" ]; then
        rm -rf "${BASE:?}/releases/$d"
        echo "pruned $d"
    fi
done
