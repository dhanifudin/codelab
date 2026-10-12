#!/usr/bin/env bash
# Shared helpers for provision scripts. Source, do not execute.
# Every helper is idempotent and reports "changed" or "unchanged".

CHANGED=0

log()  { printf '[provision] %s\n' "$*"; }
warn() { printf '[provision] WARN: %s\n' "$*" >&2; }
die()  { printf '[provision] ERROR: %s\n' "$*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"; }

# render_template <template> <outfile>: replaces @VAR@ with the value of $VAR.
# Fails when a placeholder has no matching variable.
render_template() {
    local tpl=$1 out=$2 var val content
    content=$(cat "$tpl")
    for var in $(grep -o '@[A-Z_]\+@' "$tpl" | sort -u | tr -d '@'); do
        [ -n "${!var+x}" ] || die "template $tpl uses @${var}@ but \$$var is unset"
        val=${!var}
        content=${content//@${var}@/$val}
    done
    printf '%s\n' "$content" >"$out"
}

# install_if_changed <src> <dest> <mode> [owner:group]
# Installs only when content, mode or owner differ. Returns 0 either way,
# sets CHANGED=1 when the file was written.
install_if_changed() {
    local src=$1 dest=$2 mode=$3 owner=${4:-root:root}
    if [ -f "$dest" ] && cmp -s "$src" "$dest" \
        && [ "$(stat -c '%a' "$dest")" = "${mode#0}" ] \
        && [ "$(stat -c '%U:%G' "$dest")" = "$owner" ]; then
        log "unchanged: $dest"
        return 0
    fi
    install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$src" "$dest"
    log "changed:   $dest"
    CHANGED=1
}

# ensure_line <file> <line>: append the line when absent.
ensure_line() {
    local file=$1 line=$2
    if [ -f "$file" ] && grep -qxF -- "$line" "$file"; then
        log "unchanged: $file (line present)"
    else
        printf '%s\n' "$line" >>"$file"
        log "changed:   $file (line added)"
        CHANGED=1
    fi
}

# cert_covers <san-text> <name>: true when a certificate with these SANs (the output of
# `openssl x509 -ext subjectAltName`) is valid for <name>. A wildcard name is only covered by the
# identical wildcard; a plain name is covered by itself or by *.parent when it is exactly one label deep.
cert_covers() {
    local san=$1 name=$2 sans c suffix label
    sans=$(grep -oE 'DNS:[^, ]+' <<<"$san" | cut -c5-)
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        [ "$c" = "$name" ] && return 0
        if [[ "$c" == \*.* && "$name" != \** ]]; then
            suffix=${c#\*}                      # .halokes.com
            label=${name%"$suffix"}              # abs
            [ "$label" != "$name" ] && [ -n "$label" ] && [[ "$label" != *.* ]] && return 0
        fi
    done <<<"$sans"
    return 1
}
