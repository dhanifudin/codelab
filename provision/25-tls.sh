# Sourced by provision.sh. Let's Encrypt origin cert via DNS-01 on Cloudflare (TLS=letsencrypt-cloudflare).
# Needs no inbound port and works behind the Cloudflare proxy. Skipped for TLS=none.
if [ "$TLS" != letsencrypt-cloudflare ]; then
    log "skipped:   TLS=$TLS"
    return 0
fi

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

# Does the live cert already cover every name?
covered=1
live="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
if [ -f "$live" ]; then
    san=$(openssl x509 -in "$live" -noout -ext subjectAltName 2>/dev/null || true)
    for n in $SERVER_NAMES; do
        grep -qw "DNS:$n" <<<"$san" || covered=0
    done
else
    covered=0
fi

if [ "$covered" = 1 ]; then
    log "unchanged: certificate for $SERVER_NAMES present (renewal: certbot.timer)"
else
    [ -f "$cred_file" ] || die "no $cred_file: set CF_CERTBOT_TOKEN (see docs/cloudflare-migration.md)"
    args=()
    for n in $SERVER_NAMES; do args+=(-d "$n"); done
    if [ -n "${CERTBOT_EMAIL:-}" ]; then acct=(-m "$CERTBOT_EMAIL"); else acct=(--register-unsafely-without-email); fi
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$cred_file" \
        --dns-cloudflare-propagation-seconds 30 --cert-name "$DOMAIN" "${args[@]}" \
        --expand --keep-until-expiring -n --agree-tos "${acct[@]}" \
        --deploy-hook "systemctl reload nginx"
    log "changed:   certificate issued for $SERVER_NAMES"
    CHANGED=1
fi
