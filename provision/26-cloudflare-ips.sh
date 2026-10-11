# Sourced by provision.sh. nginx snippet restoring the real client IP behind the Cloudflare proxy.
# Only rendered for Cloudflare-fronted sites; vhosts opt in with `include snippets/cloudflare-realip.conf;`.
if [ "$TLS" != letsencrypt-cloudflare ]; then
    log "skipped:   not behind Cloudflare"
    return 0
fi

snippet=/etc/nginx/snippets/cloudflare-realip.conf
cf_tmp=$(mktemp)
ok=1
{
    echo "# Managed by codelab provision/26-cloudflare-ips.sh. Ranges: https://www.cloudflare.com/ips/"
    for fam in ips-v4 ips-v6; do
        ranges=$(curl -fsS --max-time 20 "https://www.cloudflare.com/$fam") || { ok=0; break; }
        while IFS= read -r cidr; do
            [[ "$cidr" =~ ^[0-9a-fA-F:.]+/[0-9]+$ ]] || { ok=0; break 2; }
            echo "set_real_ip_from $cidr;"
        done <<<"$ranges"
    done
    echo "real_ip_header CF-Connecting-IP;"
    echo "real_ip_recursive on;"
} >"$cf_tmp" || ok=0

if [ "$ok" = 1 ]; then
    install -d -m 755 /etc/nginx/snippets
    install_if_changed "$cf_tmp" "$snippet" 644
elif [ -f "$snippet" ]; then
    warn "could not fetch Cloudflare ranges; keeping existing $snippet"
else
    rm -f "$cf_tmp"
    die "could not fetch Cloudflare IP ranges and no snippet exists"
fi
rm -f "$cf_tmp"
