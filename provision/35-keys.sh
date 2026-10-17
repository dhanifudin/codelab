# Sourced by provision.sh. Go sites: root-only signing and session keys in /etc/codelab/$SITE/,
# created once and never overwritten or printed. systemd hands them to the service (LoadCredential=).
if [ "$KIND" != go ]; then
    log "skipped:   keys (KIND=$KIND)"
    return 0
fi

key_dir=/etc/codelab/$SITE
install -d -m 700 -o root -g root "$key_dir"

make_key() { # make_key <file> <generator command...>
    local file=$1; shift
    if [ -s "$file" ]; then
        log "unchanged: $file"
        return 0
    fi
    ( umask 077; "$@" >"$file.new" ) || { rm -f "$file.new"; die "could not generate $file"; }
    chmod 400 "$file.new"
    mv "$file.new" "$file"
    log "changed:   $file created (mode 400, root)"
    CHANGED=1
}

# Ed25519 seed: the last 32 bytes of the PKCS#8 DER encoding, base64, as `licensed keygen` writes it.
ed25519_seed() { openssl genpkey -algorithm ed25519 -outform DER | tail -c 32 | base64 -w0; echo; }
random_key()   { head -c 32 /dev/urandom | base64 -w0; echo; }

make_key "$key_dir/signing.key" ed25519_seed
make_key "$key_dir/session.key" random_key

# The public half is not a secret: it is what the desktop apps embed (bibik packages/core/src/license/keys.ts).
pub=$({ printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'; base64 -d <"$key_dir/signing.key"; } \
    | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64 -w0)
log "signing public key (base64): $pub"
