#!/usr/bin/env bash
# Runs on the VPS as the deploy user: bash -s -- <site> [sha]
# Points `current` at the previous release (or the given sha). Database
# migrations are NOT reverted; only roll back across migration-free releases.
set -euo pipefail

SITE=${1:?site}
# shellcheck source=/dev/null
source "/etc/codelab/$SITE.conf"

active=$(basename "$(readlink "$BASE/current")")
if [ -n "${2:-}" ]; then
    target=$2
else
    target=$(ls -1t "$BASE/releases" | grep -vx "$active" | head -1 || true)
fi
[ -n "$target" ] && [ -d "$BASE/releases/$target" ] || { echo "no release to roll back to" >&2; exit 1; }

ln -sfn "releases/$target" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"
sudo -n /usr/bin/systemctl reload "php$PHP_VERSION-fpm"
echo "rolled back: $active -> $target"
