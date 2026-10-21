# Sourced by provision.sh. Certificates for TLS=none | letsencrypt-cloudflare | letsencrypt-webroot.
#   letsencrypt-cloudflare  DNS-01 through the Cloudflare API: no inbound port, wildcards allowed,
#                           works behind the Cloudflare proxy (zones we control).
#   letsencrypt-webroot     HTTP-01 over port 80 for zones we do not control (the DNS owner only has to
#                           point the A record here). Skips cleanly until DNS points at this server.
# Sets TLS_READY=1 when a certificate covering CERT_NAMES exists.
case "$TLS" in
    none) log "skipped:   TLS=none"; return 0 ;;
    letsencrypt-cloudflare | letsencrypt-webroot) ;;
    *) die "unknown TLS mode: $TLS" ;;
esac

# Does the live cert already cover every name?
cert_is_covered() {
    local live="/etc/letsencrypt/live/$DOMAIN/fullchain.pem" san n
    [ -f "$live" ] || return 1
    san=$(openssl x509 -in "$live" -noout -ext subjectAltName 2>/dev/null || true)
    for n in $CERT_NAMES; do
        cert_covers "$san" "$n" || return 1
    done
}

if [ -n "${CERTBOT_EMAIL:-}" ]; then acct=(-m "$CERTBOT_EMAIL"); else acct=(--register-unsafely-without-email); fi

if [ "$TLS" = letsencrypt-webroot ]; then
    case " $CERT_NAMES " in *"*"*) die "TLS=letsencrypt-webroot cannot issue wildcard names ($CERT_NAMES)" ;; esac
    install -d -m 755 /var/www/letsencrypt

    if cert_is_covered; then
        log "unchanged: certificate for $CERT_NAMES present (renewal: certbot.timer)"
        TLS_READY=1
        return 0
    fi

    # 1. Every name must already point at this server, or Let's Encrypt cannot validate it.
    pending=
    if [ "${TLS_DNS_CHECK:-strict}" != skip ]; then
        for n in $CERT_NAMES; do
            resolves_to_this_host "$n" || pending+=" $n($(resolve_ipv4 "$n" | tr '\n' ',' | sed 's/,$//'))"
        done
    fi
    if [ -n "$pending" ]; then
        log "pending:   DNS does not point at this server yet for:$pending (no certificate; re-run after the record changes)"
        return 0
    fi
    # 2. The plain-HTTP vhost (with the ACME location) must already be live.
    if [ ! -e "/etc/nginx/sites-enabled/$DOMAIN.conf" ]; then
        log "pending:   vhost for $DOMAIN not installed yet (certificate is requested on the next run)"
        return 0
    fi
    # 3. Issue. A failure is not fatal: the site keeps serving over HTTP and the next run retries.
    set -f
    args=(); for n in $CERT_NAMES; do args+=(-d "$n"); done
    set +f
    if certbot certonly --webroot -w /var/www/letsencrypt --cert-name "$DOMAIN" "${args[@]}" \
        --expand --keep-until-expiring -n --agree-tos "${acct[@]}" --deploy-hook "systemctl reload nginx"; then
        log "changed:   certificate issued for $CERT_NAMES"
        TLS_READY=1
        CHANGED=1
    else
        warn "certbot failed for $CERT_NAMES (see /var/log/letsencrypt/letsencrypt.log); continuing over HTTP"
    fi
    return 0
fi

# --- letsencrypt-cloudflare (DNS-01) ---
cred_dir=/etc/letsencrypt/cloudflare
cred_file="$cred_dir/$SITE.ini"

# Token with DNS:Edit on the zone only, via $CF_CERTBOT_TOKEN (stdin from provision-remote.sh, never argv).
dpkg-query -W -f='${Status}' python3-certbot-dns-cloudflare 2>/dev/null | grep -q "install ok installed" || {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-certbot-dns-cloudflare
    log "changed:   installed python3-certbot-dns-cloudflare"
}

if [ -n "${CF_CERTBOT_TOKEN:-}" ]; then
    [[ "$CF_CERTBOT_TOKEN" =~ ^[A-Za-z0-9_-]{20,}$ ]] || die "CF_CERTBOT_TOKEN has an unexpected format"
    install -d -m 700 "$cred_dir"
    tmp_cred=$(umask 077; mktemp)
    printf 'dns_cloudflare_api_token = %s\n' "$CF_CERTBOT_TOKEN" >"$tmp_cred"
    install_if_changed "$tmp_cred" "$cred_file" 600
    rm -f "$tmp_cred"
fi

if cert_is_covered; then
    log "unchanged: certificate for $CERT_NAMES present (renewal: certbot.timer)"
else
    [ -f "$cred_file" ] || die "no $cred_file: set CF_CERTBOT_TOKEN (see docs/cloudflare-migration.md)"
    args=()
    # `set -f`: a wildcard name such as *.example.com must never be glob-expanded.
    set -f
    for n in $CERT_NAMES; do args+=(-d "$n"); done
    set +f
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$cred_file" \
        --dns-cloudflare-propagation-seconds 30 --cert-name "$DOMAIN" "${args[@]}" \
        --expand --keep-until-expiring -n --agree-tos "${acct[@]}" \
        --deploy-hook "systemctl reload nginx"
    log "changed:   certificate issued for $CERT_NAMES"
    CHANGED=1
fi
TLS_READY=1
