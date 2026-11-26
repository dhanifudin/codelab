# Sourced by provision.sh. Tools, script and secrets for an encrypted backup of a site's database and
# shared/storage to a private S3-compatible bucket (Cloudflare R2). Only for sites with BACKUP=1.
# Secrets come from the environment (stdin of provision-remote.sh) and are stored root-only:
# BACKUP_R2_ACCOUNT_ID, BACKUP_R2_ACCESS_KEY_ID, BACKUP_R2_SECRET_ACCESS_KEY, BACKUP_R2_BUCKET and
# BACKUP_AGE_RECIPIENT (an age public key; the private key stays with the owner, never on the server).
if [ "${BACKUP:-0}" != 1 ]; then
    log "skipped:   BACKUP is not enabled"
    return 0
fi

for pkg in age rclone; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || {
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
        log "changed:   installed $pkg"
    }
done

backup_env="/etc/codelab/$SITE.backup.env"
backup_vars="BACKUP_R2_ACCOUNT_ID BACKUP_R2_ACCESS_KEY_ID BACKUP_R2_SECRET_ACCESS_KEY BACKUP_R2_BUCKET BACKUP_AGE_RECIPIENT"
given=0
for v in $backup_vars; do [ -z "${!v:-}" ] || given=$((given + 1)); done

if [ "$given" = 5 ]; then
    [[ "$BACKUP_AGE_RECIPIENT" =~ ^age1[a-z0-9]{20,}$ ]] || die "BACKUP_AGE_RECIPIENT must be an age public key (age1...)"
    tmp_env=$(umask 077; mktemp)
    for v in $backup_vars; do printf '%s=%q\n' "$v" "${!v}"; done >"$tmp_env"
    install_if_changed "$tmp_env" "$backup_env" 600
    rm -f "$tmp_env"
elif [ "$given" != 0 ]; then
    die "set all of: $backup_vars"
fi

CHANGED=0
install -d -m 755 /usr/local/lib/codelab
install_if_changed "$HERE/files/backup.sh" /usr/local/lib/codelab/backup.sh 755

# The timer comes from sites/<site>/backup.timer (provision/30-site.sh); it skips until the secrets exist.
[ -f "$backup_env" ] || log "pending:   no $backup_env yet (set the BACKUP_* values and provision again); backups are OFF"
