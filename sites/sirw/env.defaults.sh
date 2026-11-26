# Sourced by scripts/render-env.sh before rendering. Sets defaults for optional SIRW_* variables.
export SIRW_APP_URL=${SIRW_APP_URL:-https://rw05tanjungrejo.or.id}

export SIRW_MAIL_PORT=${SIRW_MAIL_PORT:-587}
export SIRW_MAIL_ENCRYPTION=${SIRW_MAIL_ENCRYPTION:-tls}
export SIRW_MAIL_FROM=${SIRW_MAIL_FROM:-no-reply@rw05tanjungrejo.or.id}

# The public letter service stays off until this repository variable is "true".
export SIRW_LETTERS_ENABLED=${SIRW_LETTERS_ENABLED:-false}
export SIRW_TURNSTILE_SITE_KEY=${SIRW_TURNSTILE_SITE_KEY:-}
export SIRW_TURNSTILE_SECRET_KEY=${SIRW_TURNSTILE_SECRET_KEY:-}

# Uploads stay on this server until SIRW_FILES_DISK=r2; then the six R2 values are mandatory.
export SIRW_FILES_DISK=${SIRW_FILES_DISK:-local}
export SIRW_FILES_ACCOUNT_ID=${SIRW_FILES_ACCOUNT_ID:-}
export SIRW_FILES_KEY_ID=${SIRW_FILES_KEY_ID:-}
export SIRW_FILES_SECRET=${SIRW_FILES_SECRET:-}
export SIRW_FILES_PUBLIC_BUCKET=${SIRW_FILES_PUBLIC_BUCKET:-}
export SIRW_FILES_PRIVATE_BUCKET=${SIRW_FILES_PRIVATE_BUCKET:-}
export SIRW_FILES_PUBLIC_URL=${SIRW_FILES_PUBLIC_URL:-}
case $SIRW_FILES_DISK in
    local) export SIRW_UPLOADS_PUBLIC_DISK=public SIRW_UPLOADS_PRIVATE_DISK=local ;;
    r2) export SIRW_UPLOADS_PUBLIC_DISK=r2_public SIRW_UPLOADS_PRIVATE_DISK=r2_private
        ENV_REQUIRED="${ENV_REQUIRED:-} SIRW_FILES_ACCOUNT_ID SIRW_FILES_KEY_ID SIRW_FILES_SECRET SIRW_FILES_PUBLIC_BUCKET SIRW_FILES_PRIVATE_BUCKET SIRW_FILES_PUBLIC_URL" ;;
    *) echo "SIRW_FILES_DISK must be local or r2" >&2; exit 1 ;;
esac
