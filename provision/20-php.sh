# Sourced by provision.sh. PHP-FPM $PHP_VERSION from the ondrej PPA (already configured on this host).
# Only installs php${PHP_VERSION}-* packages; other PHP versions and the `php` CLI alternative are untouched.
pkgs=()
for ext in fpm cli common mysql gd zip mbstring xml curl intl bcmath; do
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
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    CHANGED=1
fi

# The stock pool would sit idle on its own socket; disable it.
stock=/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
if [ -f "$stock" ]; then
    mv "$stock" "$stock.disabled"
    log "changed:   disabled stock pool $stock"
else
    log "unchanged: stock pool already disabled"
fi

systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1 || true
