# Site configuration reference

Everything a site needs lives in `sites/<site>/`. Provisioning and deploys read these files; nothing is edited by hand on the server.

## Files

| File | Used by | Purpose |
|---|---|---|
| `site.conf` | provision, deploy workflow, `render-env.sh`, `cf-dns.sh` | Non-secret settings (table below). Installed on the VPS as `/etc/codelab/<site>.conf`. Plain `KEY=value` shell, sourced by bash. |
| `nginx.conf` | `provision/30-site.sh` | The vhost template, used when the site has no `nginx-http.conf`/`nginx-https.conf`. |
| `nginx-http.conf`, `nginx-https.conf`, `app.conf` | `provision/30-site.sh` | Optional split used by `TLS=letsencrypt-webroot`: HTTP variant (until a certificate exists), HTTPS variant (after), and the shared `location` blocks installed as `/etc/nginx/snippets/<site>-app.conf`. |
| `php-fpm-pool.conf` | `provision/30-site.sh` | Laravel sites: dedicated fpm pool on a unix socket. |
| `systemd.service` | `provision/30-site.sh` | Go sites: the unit file. |
| `<job>.timer` + `<job>.service` | `provision/30-site.sh` | Optional scheduled jobs, installed and enabled as `<site>-<job>`. |
| `env.template` | `scripts/render-env.sh` | The application `.env`, with `${<SITE>_VAR}` placeholders. |
| `env.defaults.sh` | `scripts/render-env.sh` | Optional: defaults and derived values for optional variables (mail driver, URL scheme). |
| `shared-paths.txt` | `scripts/remote/activate.sh` | Directories that persist across releases (below). |
| `rsync-exclude.txt` | `_deploy.yml` | Files left out of the release. |
| `dns.records`, `cf-zone-settings` | `scripts/cf-dns.sh` | Cloudflare records and zone settings (Cloudflare zones we control only). |
| `app-dispatch.yml` | you, once | Copy into the app repo as `.github/workflows/notify-codelab.yml`. |

Workflows: `.github/workflows/_deploy.yml` (reusable), `deploy-<site>.yml` (thin caller), `bootstrap.yml` (generic seeder; the `site` choice list is fixed in the file), site-specific bootstrap workflows.

## `site.conf` keys

| Key | Required | Meaning |
|---|---|---|
| `SITE` | yes | Directory name; also the prefix of its secrets (`SPI_*` for `spi`). |
| `DOMAIN` | yes | Primary host; names the vhost file, certificate lineage and `BASE`. |
| `APP_REPO` | yes | `owner/name` of the app repository the deploy checks out. |
| `SERVER_NAMES` | no (`DOMAIN`) | Hosts nginx serves for this site. |
| `CERT_NAMES` | no (`SERVER_NAMES`) | Names the certificate must cover. Wildcards (`*.example.com`) only with `letsencrypt-cloudflare`. |
| `TENANTS` | no | `host:KODE ...` school hosts redirected to a yayasan portal (halokes only). |
| `KIND` | no (`laravel`) | `laravel` or `go`. |
| `PHP_VERSION`, `PHP_EXTENSIONS` | Laravel | PHP version and the `php<ver>-<ext>` packages to install if missing. |
| `DISABLE_STOCK_POOL` | no (`0`) | `1` only for a PHP version that serves no other site. |
| `POOL_NAME` | Laravel | fpm pool name (socket `/run/php/php<ver>-fpm-<pool>.sock`). |
| `SERVICE`, `APP_PORT` | Go | systemd unit name and the localhost port. |
| `DEPLOY_USER`, `WEB_GROUP` | yes | Owner of the release tree (`deploy`, `www-data`). |
| `BASE` | yes | `/var/www/<domain>`; holds `releases/`, `shared/`, `current`. |
| `KEEP_RELEASES` | yes | Releases retained. |
| `DB_NAME`, `DB_USER` | yes | Database and user created by `provision/40-db.sh`; password from `<SITE>_DB_PASSWORD`. |
| `TLS` | no (`none`) | `none`, `letsencrypt-cloudflare` (DNS-01) or `letsencrypt-webroot` (HTTP-01). |
| `TLS_DNS_CHECK` | no | `skip` disables the "DNS points here" check for webroot mode (proxied records). |
| `PUBLIC_IP` | no | Public address when it is NATed and not configured on an interface; used by the DNS check. |
| `CF_ZONE` | Cloudflare | Zone name for `cf-dns.sh`. |
| `NODE_BUILD`, `NODE_VERSION`, `PKG_MANAGER` | no | Build assets on the runner (`npm` or `pnpm`). |
| `SMOKE_PATH`, `SMOKE_SCHEME` | yes | Deploy smoke test URL, requested straight at the origin. |
| `SEED_CLASS` | with `bootstrap.yml` | Seeder class run by `scripts/remote/bootstrap.sh`. |
| `ENV_REQUIRED` | yes | Variables that must be non-empty for `render-env.sh` to succeed. |

## Secrets and variables

Naming: `<SITE>_NAME`, upper case. `render-env.sh` and `_deploy.yml` pass only the variables with the site's prefix into the template, so one site cannot read another's.

| Name | Kind | Created by | Used for |
|---|---|---|---|
| `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS` | secret (repo-wide) | `setup-github.sh` | CI to VPS |
| `APP_READ_TOKEN` | secret (repo-wide) | you ([tokens.md](tokens.md)) | check out private app repos |
| `<SITE>_APP_KEY`, `<SITE>_DB_PASSWORD` | secret | `setup-github.sh` (generated) | `.env` and database user |
| `<SITE>_ADMIN_NAME`, `_EMAIL`, `_PASSWORD` (spi also `_USERNAME`) | secret | `setup-github.sh` | first admin at bootstrap |
| `<SITE>_MAIL_*`, `<SITE>_NOCAPTCHA_*`, ... | secret | you, when needed | optional app settings |
| `<SITE>_APP_URL` | variable | you, after HTTPS | `APP_URL` and secure cookies |
| `SPI_FILES_KEY_ID`, `SPI_FILES_SECRET`, `SPI_FILES_BUCKET`, `SPI_FILES_ENDPOINT` | secret | you ([sites/spi file storage](#spi-file-storage-cloudflare-r2)) | spi uploads on Cloudflare R2 |
| `SPI_FILES_DISK` | variable | you | where spi keeps uploads: `private` (default, the VPS) or `r2` |
| `CODELAB_DISPATCH_TOKEN` | secret in the **app** repo | you | app repo triggers the deploy |
| `CF_API_TOKEN` | local only (`cloudflare.env`) | you | `cf-dns.sh` |
| `CF_CERTBOT_TOKEN` | local only; installed root-only on the VPS | you | DNS-01 challenges |

Local store `~/.config/codelab/`: `<site>.env` (generated secrets, mode 600), `cloudflare.env`, `deploy_key` and `deploy_key.pub`. Override the directory with `CODELAB_ENV_DIR`.

## spi file storage (Cloudflare R2)

Create a bucket with public access off, and an R2 API token with **Object Read & Write** on that bucket only. Set the four secrets one at a time with `gh secret set <name> -R <this repo>` (one line each; the endpoint is `https://<account-id>.r2.cloudflarestorage.com`). Never commit the values.

To switch, on the VPS as the deploy user, in the current release:

1. With `SPI_FILES_DISK=private` deployed: `artisan files:probe r2`, `artisan files:check-references private`, `artisan files:copy private r2 --dry-run`, then without `--dry-run`, then `artisan files:check-references r2`.
2. Set the variable `SPI_FILES_DISK=r2`, deploy, and run `files:copy private r2` once more for anything uploaded in between.

**Nightly copy back.** `files-backup.timer` runs `artisan files:backup` at 02:15 WIB: new and changed files come back to `shared/storage/app/private`, so a backup of `shared/storage` covers uploads up to the last run. It does nothing while `SPI_FILES_DISK=private`. Nothing is deleted locally, and the previous version of a changed file is kept in `shared/storage/app/private-replaced/<time>/`. R2 therefore does not save disk space on the VPS. Install the timer by provisioning the site, after the app release that has the command is live. Nothing sends an alert when a run fails; check with:

```sh
systemctl list-timers spi-files-backup.timer
systemctl status spi-files-backup.service      # last result
journalctl -u spi-files-backup.service -n 50
sudo systemctl start spi-files-backup.service  # run now, for example just before taking a backup
```

To go back: run `artisan files:backup` while still on `r2`, set `private`, deploy, then run `artisan files:copy r2 private` for anything uploaded in between (it only adds missing files and reports differences).

## `shared-paths.txt`

One path per line, relative to the release, optional second column:

```
storage                         # seeded from the release the first time, then shared
public/template_dokumen         # same: committed templates are copied once
public/hasil_reviu empty        # user data: created empty, never seeded from the release
# comments and blank lines are ignored
```

At each deploy `activate.sh` replaces the release's copy of every listed path with a symlink to `shared/<path>`. Paths the app writes to but that are missing here are lost on the next deploy. Pair `empty` folders with `/public/<dir>/*` lines in `rsync-exclude.txt` so committed sample files are not even uploaded.

## `env.template` rules

- Placeholders are `${<SITE>_NAME}`; Laravel's own `${APP_NAME}` is left alone.
- Every placeholder must be defined by a secret/variable or by `env.defaults.sh`, or rendering fails with the variable name (never its value).
- Set `APP_ENV=production`, `APP_DEBUG=false`, `QUEUE_CONNECTION=sync` unless a worker is provisioned, and `MAIL_MAILER=log` until SMTP is configured.

## TLS modes

| Mode | Challenge | Needs | Behaviour |
|---|---|---|---|
| `none` | n/a | n/a | HTTP vhost only. |
| `letsencrypt-cloudflare` | DNS-01 through the Cloudflare API | `CF_CERTBOT_TOKEN`, zone on Cloudflare | Issued before the vhost is written; wildcards allowed; works behind the proxy. Provisioning installs `snippets/cloudflare-realip.conf` for real client IPs. |
| `letsencrypt-webroot` | HTTP-01 on port 80 | an A record pointing at the VPS (not proxied) | Skips with `pending:` until DNS points here and the HTTP vhost exists, then issues and switches to `nginx-https.conf`. A certbot failure leaves the site on HTTP. |

## What provisioning installs on the VPS

`/swapfile` (2 GB), `php<ver>-*` packages, `/etc/php/<ver>/fpm/pool.d/<pool>.conf`, `/etc/nginx/sites-available/<domain>.conf` (+ symlink, + snippets), `/etc/letsencrypt/{cloudflare/<site>.ini,live/<domain>}`, `/etc/codelab/<site>.{conf,shared-paths}`, `/etc/systemd/system/<site>-<job>.{service,timer}` for scheduled jobs, `/etc/sudoers.d/codelab-<site>` (the deploy user may only reload that fpm or restart that unit), the deploy key in `~deploy/.ssh/authorized_keys` (no pty, no forwarding), `/etc/logrotate.d/php<ver>-fpm-<pool>`, a monit rule for root-disk usage, the database and user, and `/var/www/<domain>/{releases,shared}`.

## Backup (`BACKUP=1`)

| Key | Meaning |
|---|---|
| `BACKUP` | `1` installs the backup script and its secrets (`provision/45-backup.sh`). Default `0`. The schedule is the site's `backup.timer` + `backup.service`. |
| `BACKUP_KEEP_DAYS` | Age after which old copies are deleted from the bucket. Default `30`. |

Secrets, in `~/.config/codelab/<site>.env` on the workstation: `BACKUP_R2_ACCOUNT_ID`, `BACKUP_R2_ACCESS_KEY_ID`, `BACKUP_R2_SECRET_ACCESS_KEY`, `BACKUP_R2_BUCKET`, `BACKUP_AGE_RECIPIENT`. See [sirw.md](sirw.md#backups) for setup and restore.
