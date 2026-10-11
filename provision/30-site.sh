# Sourced by provision.sh. Directories, fpm pool, nginx vhost, sudoers, deploy key, logrotate.
id "$DEPLOY_USER" >/dev/null 2>&1 || die "user $DEPLOY_USER does not exist"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- directories ---
for d in "$BASE" "$BASE/releases" "$BASE/shared"; do
    if [ "$(stat -c '%U:%G %a' "$d" 2>/dev/null)" = "$DEPLOY_USER:$WEB_GROUP 755" ]; then
        log "unchanged: $d"
    else
        install -d -m 755 -o "$DEPLOY_USER" -g "$WEB_GROUP" "$d"
        log "changed:   $d"
    fi
done

# --- site config readable by the deploy user (activate.sh sources it) ---
install_if_changed "$SITE_DIR/site.conf" "/etc/codelab/$SITE.conf" 644
install_if_changed "$SITE_DIR/shared-paths.txt" "/etc/codelab/$SITE.shared-paths" 644

# --- php-fpm pool ---
CHANGED=0
render_template "$SITE_DIR/php-fpm-pool.conf" "$tmp/pool.conf"
install_if_changed "$tmp/pool.conf" "/etc/php/$PHP_VERSION/fpm/pool.d/$POOL_NAME.conf" 644
if [ "$CHANGED" = 1 ] || ! systemctl is-active --quiet "php$PHP_VERSION-fpm"; then
    "php-fpm$PHP_VERSION" -t 2>&1 | sed 's/^/[php-fpm] /'
    systemctl restart "php$PHP_VERSION-fpm"
    log "changed:   php$PHP_VERSION-fpm restarted"
fi

# --- fpm log rotation ---
cat >"$tmp/logrotate" <<EOF
/var/log/php${PHP_VERSION}-fpm-${POOL_NAME}.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        /usr/lib/php/php-fpm-reload ${PHP_VERSION} >/dev/null 2>&1 || true
    endscript
}
EOF
install_if_changed "$tmp/logrotate" "/etc/logrotate.d/php${PHP_VERSION}-fpm-${POOL_NAME}" 644

# --- nginx vhost ---
CHANGED=0
render_template "$SITE_DIR/nginx.conf" "$tmp/vhost.conf"
install_if_changed "$tmp/vhost.conf" "/etc/nginx/sites-available/$DOMAIN.conf" 644
if [ "$(readlink "/etc/nginx/sites-enabled/$DOMAIN.conf" 2>/dev/null)" != "/etc/nginx/sites-available/$DOMAIN.conf" ]; then
    ln -sfn "/etc/nginx/sites-available/$DOMAIN.conf" "/etc/nginx/sites-enabled/$DOMAIN.conf"
    log "changed:   /etc/nginx/sites-enabled/$DOMAIN.conf linked"
    CHANGED=1
fi
# nginx -t must pass before every reload; on failure disable the vhost so other sites keep working.
if ! nginx -t 2>"$tmp/nginx-test"; then
    cat "$tmp/nginx-test" >&2
    rm -f "/etc/nginx/sites-enabled/$DOMAIN.conf"
    die "nginx config invalid; vhost unlinked, nginx untouched"
fi
if [ "$CHANGED" = 1 ]; then
    systemctl reload nginx
    log "changed:   nginx reloaded"
fi

# --- sudoers: deploy may reload only its own fpm ---
CHANGED=0
cat >"$tmp/sudoers" <<EOF
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl reload php$PHP_VERSION-fpm
EOF
visudo -cf "$tmp/sudoers" >/dev/null || die "generated sudoers invalid"
install_if_changed "$tmp/sudoers" "/etc/sudoers.d/codelab-$SITE" 440

# --- deploy key (public half, committed in sites/<site>/deploy.pub) ---
if [ -f "$SITE_DIR/deploy.pub" ]; then
    home=$(getent passwd "$DEPLOY_USER" | cut -d: -f6)
    install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    ensure_line "$home/.ssh/authorized_keys" \
        "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $(tr -d '\n' <"$SITE_DIR/deploy.pub")"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
else
    warn "sites/$SITE/deploy.pub missing: run scripts/setup-github.sh first, then re-provision"
fi
