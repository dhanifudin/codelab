#!/usr/bin/env bash
# Render sites/<site>/env.template to stdout from SPI_* environment variables.
# Fails (without printing secrets) when a required variable is empty.
# Usage: SPI_APP_KEY=... SPI_DB_PASSWORD=... render-env.sh spi > .env
set -euo pipefail

SITE=${1:?usage: render-env.sh <site>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$HERE/../sites/$SITE/env.template"
[ "$SITE" = spi ] || { echo "render-env.sh only knows the spi variable set" >&2; exit 1; }

for v in SPI_APP_KEY SPI_DB_PASSWORD; do
    [ -n "${!v:-}" ] || { echo "required variable $v is empty" >&2; exit 1; }
done
case $SPI_APP_KEY in base64:*) ;; *) echo "SPI_APP_KEY must look like base64:..." >&2; exit 1 ;; esac

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
export SPI_NOCAPTCHA_SECRET=${SPI_NOCAPTCHA_SECRET:-}
export SPI_NOCAPTCHA_SITEKEY=${SPI_NOCAPTCHA_SITEKEY:-}

# Explicit variable list so Laravel's own ${APP_NAME} reference is left untouched.
vars=$(grep -o '\${SPI_[A-Z_]*}' "$TEMPLATE" | sort -u | tr '\n' ' ')
envsubst "$vars" <"$TEMPLATE"
