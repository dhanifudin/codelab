# Sourced by provision.sh. 2 GB swapfile for a 4 GB host that has none.
SWAPFILE=/swapfile
SWAP_SIZE_MB=2048

if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
    log "unchanged: swap active on $SWAPFILE"
elif [ -f "$SWAPFILE" ]; then
    chmod 600 "$SWAPFILE"
    swapon "$SWAPFILE"
    log "changed:   enabled existing $SWAPFILE"
else
    avail_mb=$(df -m --output=avail / | tail -1 | tr -d ' ')
    [ "$avail_mb" -gt $((SWAP_SIZE_MB + 1024)) ] || die "not enough disk for swapfile (${avail_mb} MB free)"
    fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE"
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
    swapon "$SWAPFILE"
    log "changed:   created ${SWAP_SIZE_MB} MB $SWAPFILE"
fi

ensure_line /etc/fstab "$SWAPFILE none swap sw 0 0"

tmp=$(mktemp)
echo "vm.swappiness=10" >"$tmp"
install_if_changed "$tmp" /etc/sysctl.d/99-codelab-swap.conf 644
rm -f "$tmp"
[ "$(sysctl -n vm.swappiness)" = 10 ] || sysctl -q -p /etc/sysctl.d/99-codelab-swap.conf
