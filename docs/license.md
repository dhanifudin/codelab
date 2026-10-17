# license.dhanifudin.com

The Polinema licence service: one Go binary (`licensed`) behind nginx, local MariaDB, systemd unit
`licensed.service`. App repo: `dhanifudin/license.dhanifudin.com` (private). This is the first `KIND=go` site.

## How it differs from the Laravel sites

- `site.conf` sets `KIND=go`, `SERVICE=licensed` and `APP_PORT=8091` (the app listens on `127.0.0.1:8091`).
- No PHP-FPM pool. `provision/30-site.sh` installs `/etc/systemd/system/licensed.service` from `sites/license/systemd.service`
  and a sudoers rule that lets `deploy` run only `systemctl restart licensed.service`.
- `provision/35-keys.sh` creates `/etc/codelab/license/signing.key` (Ed25519 seed) and `session.key` once, root-only, mode 400.
  systemd passes them to the service with `LoadCredential=`; they never enter CI, git, the release or the `.env`.
  The log prints the signing **public** key (not secret); embed it in Bibik's `packages/core/src/license/keys.ts`.
- The service runs as a `DynamicUser` with `StateDirectory=license` (`/var/lib/license`, private; payment proofs go there later).
- A release is just the binary: `releases/<sha>/licensed`. `current` is switched atomically, then the unit is restarted.
  Migrations are embedded in the binary and run at start, so a rollback does not revert the schema.
- Deploys are triggered by the app repo's CI after its tests pass (`event-type: deploy-license`).
- The nginx vhost is a plain reverse proxy; nothing is served from disk.

## First-time setup

1. Google Cloud console: create an OAuth web client, authorised redirect URI
   `https://license.dhanifudin.com/auth/callback`.
2. Cloudflare: a certbot token scoped to the `dhanifudin.com` zone (DNS:Edit, Zone:Read), see `docs/tokens.md`; a separate
   DNS-admin token for `scripts/cf-dns.sh`. The zone SSL mode must be Full (strict). There is deliberately no
   `cf-zone-settings` file for this site, because those settings would apply to the whole `dhanifudin.com` zone.
3. `CF_CERTBOT_TOKEN=... scripts/setup-github.sh license codelab`. It asks for the Google client id and secret, the signing key id
   (a label such as `2026-10`) and the admin emails, then sets the secrets `LICENSE_DB_PASSWORD`, `LICENSE_GOOGLE_CLIENT_ID`,
   `LICENSE_GOOGLE_CLIENT_SECRET` and the variables `LICENSE_KEY_ID`, `LICENSE_ADMIN_EMAILS` (and `LICENSE_PAYMENT_TEXT` when given in
   the environment). Reuses the existing deploy key.
4. The app repo is private, so `APP_READ_TOKEN` must be able to read it: add `dhanifudin/license.dhanifudin.com` to that
   fine-grained token's repositories.
5. In the app repo: `gh secret set CODELAB_DISPATCH_TOKEN --repo dhanifudin/license.dhanifudin.com` (token steps in `docs/tokens.md`).
6. `scripts/provision-remote.sh codelab license`, twice. The second run must log only `unchanged:` and `skipped:`.
   Copy the printed `signing public key`.
7. Run the **Deploy license** workflow by hand (Actions, Run workflow). Smoke test: `GET /healthz` must return 200.
8. DNS last: `scripts/cf-dns.sh license --dry-run`, then for real. (A record pointing at an origin that does not yet serve the host
   shows another site's certificate.)
9. Set the catalogue on the VPS, with the service environment (the unit's `.env`):
   ```
   ssh codelab
   sudo systemd-run --quiet --pipe --wait -p DynamicUser=yes -p EnvironmentFile=/var/www/license.dhanifudin.com/shared/.env \
     /var/www/license.dhanifudin.com/current/licensed product set -key bibik -name Bibik -trial-days 14
   ```
   `licensed plan set ...` the same way. (Prices are data, never code.)

## Operations

- Logs: `journalctl -u licensed`, nginx logs in `/var/log/nginx/license.*.log`.
- Manual rollback: `ssh codelab 'sudo -u deploy bash -s -- license' < scripts/remote/rollback.sh`.
- Key rotation: create a new key id, move the old public key into `LICENSE_EXTRA_PUBLIC_KEYS` (see the app's `main.go`), then replace
  `/etc/codelab/license/signing.key` (delete it and re-run provisioning) and restart.
- Never copy `/etc/codelab/license/*.key` off the host or into chat.
