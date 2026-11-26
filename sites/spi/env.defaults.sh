# Sourced by scripts/render-env.sh before rendering. Sets defaults for optional SPI_* variables.
export SPI_APP_URL=${SPI_APP_URL:-http://spi.polinema.ac.id}
case $SPI_APP_URL in https://*) export SPI_SESSION_SECURE=true ;; *) export SPI_SESSION_SECURE=false ;; esac

# Mail stays on the log driver until an SMTP host is configured.
if [ -n "${SPI_MAIL_HOST:-}" ]; then export SPI_MAIL_MAILER=smtp; else export SPI_MAIL_MAILER=log; fi
export SPI_MAIL_HOST=${SPI_MAIL_HOST:-}
export SPI_MAIL_PORT=${SPI_MAIL_PORT:-587}
export SPI_MAIL_USERNAME=${SPI_MAIL_USERNAME:-}
export SPI_MAIL_PASSWORD=${SPI_MAIL_PASSWORD:-}
export SPI_MAIL_ENCRYPTION=${SPI_MAIL_ENCRYPTION:-tls}
export SPI_MAIL_FROM=${SPI_MAIL_FROM:-no-reply@spi.polinema.ac.id}
export SPI_MAIL_SCAN_AUDIT_TO=${SPI_MAIL_SCAN_AUDIT_TO:-}
export SPI_NOCAPTCHA_SECRET=${SPI_NOCAPTCHA_SECRET:-}
export SPI_NOCAPTCHA_SITEKEY=${SPI_NOCAPTCHA_SITEKEY:-}

# Uploaded files stay on this server until SPI_FILES_DISK=r2; then the four R2 values are mandatory.
# They may be set earlier, so `php artisan files:probe r2` and `files:copy private r2` can run before the switch.
export SPI_FILES_DISK=${SPI_FILES_DISK:-private}
export SPI_FILES_KEY_ID=${SPI_FILES_KEY_ID:-}
export SPI_FILES_SECRET=${SPI_FILES_SECRET:-}
export SPI_FILES_BUCKET=${SPI_FILES_BUCKET:-}
export SPI_FILES_ENDPOINT=${SPI_FILES_ENDPOINT:-}
case $SPI_FILES_DISK in
    private) ;;
    r2) ENV_REQUIRED="${ENV_REQUIRED:-} SPI_FILES_KEY_ID SPI_FILES_SECRET SPI_FILES_BUCKET SPI_FILES_ENDPOINT" ;;
    *) echo "SPI_FILES_DISK must be private or r2" >&2; exit 1 ;;
esac
