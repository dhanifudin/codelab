#!/usr/bin/env bash
# Back up one site: database and shared/storage, encrypted with age, copied to a bucket.
# Usage (as root): backup.sh <site>     Installed by provision/45-backup.sh, run by
# <site>-backup.timer. CODELAB_ETC and BACKUP_TARGET exist for testing.
set -euo pipefail
umask 077

SITE=${1:?usage: backup.sh <site>}
ETC=${CODELAB_ETC:-/etc/codelab}
# shellcheck source=/dev/null
source "$ETC/$SITE.conf"
# shellcheck source=/dev/null
source "$ETC/$SITE.backup.env"
: "${DB_NAME:?}" "${BASE:?}" "${BACKUP_AGE_RECIPIENT:?}"
KEEP_DAYS=${BACKUP_KEEP_DAYS:-30}

# rclone reads the bucket credentials from the environment, so they never appear in arguments.
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=${BACKUP_R2_ACCESS_KEY_ID:-}
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=${BACKUP_R2_SECRET_ACCESS_KEY:-}
export RCLONE_CONFIG_R2_ENDPOINT="https://${BACKUP_R2_ACCOUNT_ID:-}.r2.cloudflarestorage.com"
TARGET=${BACKUP_TARGET:-r2:${BACKUP_R2_BUCKET:?}/$SITE}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
work=$(mktemp -d /var/tmp/codelab-backup.XXXXXX)
trap 'rm -rf "$work"' EXIT

mysqldump --single-transaction --quick --routines --no-tablespaces "$DB_NAME" \
    | gzip | age -r "$BACKUP_AGE_RECIPIENT" >"$work/db-$stamp.sql.gz.age"

# Caches, sessions and logs are not worth restoring.
# tar exits 1 when a file changed while it was read, which is normal on a live site.
{
    tar -C "$BASE/shared" --exclude=storage/framework --exclude=storage/logs -czf - storage || [ "$?" = 1 ]
} | age -r "$BACKUP_AGE_RECIPIENT" >"$work/storage-$stamp.tar.gz.age"

rclone copy "$work" "$TARGET"
# Old copies are removed only after the new ones were uploaded.
rclone delete --min-age "${KEEP_DAYS}d" --include '*.age' "$TARGET"
echo "backup of $SITE finished: $stamp"
