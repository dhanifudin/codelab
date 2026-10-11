# Sourced by provision.sh. PHP-FPM $PHP_VERSION from the ondrej PPA (already configured on this host).
# Only installs missing php${PHP_VERSION}-* packages; other PHP versions and the `php` CLI alternative are untouched.
# Note: installing an extension for an fpm that already runs makes dpkg reload it (graceful).
pkgs=()
for ext in $PHP_EXTENSIONS; do
    pkgs+=("php${PHP_VERSION}-${ext}")
done

missing=()
for p in "${pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
done

if [ ${#missing[@]} -eq 0 ]; then
    log "unchanged: PHP ${PHP_VERSION} packages installed"
else
    grep -rqs ondrej /etc/apt/sources.list.d || die "ondrej PPA not configured"
    log "changed:   installing ${missing[*]}"
    # Unrelated repos on this host may be broken (e.g. an unsigned PPA); fall back to the existing index.
    apt-get update -qq || warn "apt-get update failed; using the existing package index"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    CHANGED=1
fi

# A freshly installed fpm ships an idle stock pool; disable it. Never do this on a
# PHP version that already serves other sites (DISABLE_STOCK_POOL=0).
stock=/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
if [ "$DISABLE_STOCK_POOL" = 1 ] && [ -f "$stock" ]; then
    mv "$stock" "$stock.disabled"
    log "changed:   disabled stock pool $stock"
else
    log "unchanged: stock pool left as is (DISABLE_STOCK_POOL=$DISABLE_STOCK_POOL)"
fi

systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1 || true
