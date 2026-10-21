# Sourced by provision.sh. Directories, fpm pool (laravel) or systemd unit (go), nginx vhost, sudoers, deploy key, logrotate.
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

if [ "$KIND" != go ]; then
    # --- php-fpm pool ---
    # The fpm master may already serve other sites: validate first, reload gracefully, never restart.
    CHANGED=0
    render_template "$SITE_DIR/php-fpm-pool.conf" "$tmp/pool.conf"
    pool_file="/etc/php/$PHP_VERSION/fpm/pool.d/$POOL_NAME.conf"
    install_if_changed "$tmp/pool.conf" "$pool_file" 644
    if [ "$CHANGED" = 1 ]; then
        if ! "php-fpm$PHP_VERSION" -t 2>"$tmp/fpm-test"; then
            cat "$tmp/fpm-test" >&2
            rm -f "$pool_file"
            die "php-fpm config invalid; pool removed, running fpm untouched"
        fi
    fi
    if ! systemctl is-active --quiet "php$PHP_VERSION-fpm"; then
        systemctl start "php$PHP_VERSION-fpm"
        log "changed:   php$PHP_VERSION-fpm started"
    elif [ "$CHANGED" = 1 ]; then
        systemctl reload "php$PHP_VERSION-fpm"
        log "changed:   php$PHP_VERSION-fpm reloaded"
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
fi

# --- nginx vhost ---
# TENANTS="host:KODE ..." maps a school host to its yayasan portal (see sites/halokes/nginx.conf).
TENANT_HOSTS=; TENANT_MAP=
for t in $TENANTS; do
    [[ "$t" =~ ^[a-z0-9.-]+:[A-Za-z0-9_-]+$ ]] || die "bad TENANTS entry: $t (want host:KODE)"
    TENANT_HOSTS+="${t%%:*} "
    TENANT_MAP+="    ${t%%:*} ${t##*:};"$'\n'
done
TENANT_HOSTS=${TENANT_HOSTS% }
CHANGED=0
vhost_file="/etc/nginx/sites-available/$DOMAIN.conf"
snippet_file="/etc/nginx/snippets/$SITE-app.conf"
# Remember what is live so a bad render can be rolled back instead of taking the site offline.
[ ! -f "$vhost_file" ] || cp -p "$vhost_file" "$tmp/vhost.prev"
[ ! -f "$snippet_file" ] || cp -p "$snippet_file" "$tmp/snippet.prev"

# Optional shared locations, included by the http and https variants.
if [ -f "$SITE_DIR/app.conf" ]; then
    render_template "$SITE_DIR/app.conf" "$tmp/app.conf"
    install_if_changed "$tmp/app.conf" "$snippet_file" 644
fi
# Template: HTTPS variant once a certificate exists, else the HTTP variant, else the single nginx.conf.
vhost_tpl="$SITE_DIR/nginx.conf"
if [ -f "$SITE_DIR/nginx-https.conf" ] && [ "${TLS_READY:-0}" = 1 ]; then
    vhost_tpl="$SITE_DIR/nginx-https.conf"
elif [ -f "$SITE_DIR/nginx-http.conf" ]; then
    vhost_tpl="$SITE_DIR/nginx-http.conf"
fi
render_template "$vhost_tpl" "$tmp/vhost.conf"
install_if_changed "$tmp/vhost.conf" "$vhost_file" 644
if [ "$(readlink "/etc/nginx/sites-enabled/$DOMAIN.conf" 2>/dev/null)" != "$vhost_file" ]; then
    ln -sfn "$vhost_file" "/etc/nginx/sites-enabled/$DOMAIN.conf"
    log "changed:   /etc/nginx/sites-enabled/$DOMAIN.conf linked"
    CHANGED=1
fi
# nginx -t must pass before every reload. On failure put the previous files back (or unlink a new vhost)
# so other sites, and this one if it was already live, keep working.
if ! nginx -t 2>"$tmp/nginx-test"; then
    cat "$tmp/nginx-test" >&2
    if [ -f "$tmp/vhost.prev" ]; then
        cp -p "$tmp/vhost.prev" "$vhost_file"
        [ ! -f "$tmp/snippet.prev" ] || cp -p "$tmp/snippet.prev" "$snippet_file"
        nginx -t 2>/dev/null && systemctl reload nginx || true
        die "nginx config invalid; previous vhost restored"
    fi
    rm -f "/etc/nginx/sites-enabled/$DOMAIN.conf"
    die "nginx config invalid; vhost unlinked, nginx untouched"
fi
if [ "$CHANGED" = 1 ]; then
    systemctl reload nginx
    log "changed:   nginx reloaded"
fi

# --- systemd unit (go sites) ---
if [ "$KIND" = go ]; then
    [[ "$APP_PORT" =~ ^[0-9]+$ ]] || die "APP_PORT must be a number"
    [[ "$SERVICE" =~ ^[a-z0-9-]+$ ]] || die "SERVICE must be a unit name"
    CHANGED=0
    render_template "$SITE_DIR/systemd.service" "$tmp/unit"
    install_if_changed "$tmp/unit" "/etc/systemd/system/$SERVICE.service" 644
    [ "$CHANGED" = 0 ] || systemctl daemon-reload
    systemctl enable "$SERVICE.service" >/dev/null 2>&1 || true
    # A port held by something other than this unit would make the first deploy fail late.
    if [ -n "$(ss -ltnH "sport = :$APP_PORT")" ] && ! systemctl is-active --quiet "$SERVICE.service"; then
        die "port $APP_PORT is already in use by another process"
    fi
fi

# --- sudoers: deploy may reload only its own fpm, or restart only its own unit ---
CHANGED=0
if [ "$KIND" = go ]; then
    cat >"$tmp/sudoers" <<EOF
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart $SERVICE.service
EOF
else
    cat >"$tmp/sudoers" <<EOF
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl reload php$PHP_VERSION-fpm
EOF
fi
visudo -cf "$tmp/sudoers" >/dev/null || die "generated sudoers invalid"
install_if_changed "$tmp/sudoers" "/etc/sudoers.d/codelab-$SITE" 440

# --- deploy key (public half, committed as deploy.pub at the repo root) ---
if [ -f "$ROOT_DIR/deploy.pub" ]; then
    home=$(getent passwd "$DEPLOY_USER" | cut -d: -f6)
    install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    ensure_line "$home/.ssh/authorized_keys" \
        "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $(tr -d '\n' <"$ROOT_DIR/deploy.pub")"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
else
    warn "deploy.pub missing: run scripts/setup-github.sh first, then re-provision"
fi
