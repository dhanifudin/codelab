# Sourced by provision.sh. Root-disk usage rule for monit (shared by all sites; disk is the tight resource).
# Without a `set alert` target in monitrc, monit only writes to /var/log/monit.log.
if ! command -v monit >/dev/null 2>&1 || ! grep -qs '^include /etc/monit/conf.d/' /etc/monit/monitrc; then
    log "skipped:   monit not installed or conf.d not included"
    return 0
fi

cat >"$tmp/monit-disk" <<'MONIT'
check filesystem codelab_rootfs with path /
    if space usage > 90% then alert
    if inode usage > 90% then alert
MONIT
CHANGED=0
install_if_changed "$tmp/monit-disk" /etc/monit/conf.d/codelab-disk 600
if [ "$CHANGED" = 1 ]; then
    if monit -t >/dev/null 2>"$tmp/monit-test"; then
        systemctl reload monit
        log "changed:   monit reloaded"
    else
        cat "$tmp/monit-test" >&2
        rm -f /etc/monit/conf.d/codelab-disk
        warn "monit config invalid; rule removed"
    fi
fi
