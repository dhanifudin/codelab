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
