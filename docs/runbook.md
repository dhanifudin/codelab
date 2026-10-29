# Runbook: put a site on the codelab VPS

This is the end-to-end procedure used for `halokes.com`, `spi.polinema.ac.id` and `license.dhanifudin.com`. Follow it top to bottom for a new site, or jump to a section to operate an existing one. Companion documents:

- [site-config-reference.md](site-config-reference.md): every file and `site.conf` key
- [tokens.md](tokens.md): where each token comes from (click paths and permissions)
- [troubleshooting.md](troubleshooting.md): symptoms, causes, fixes
- Per-site notes: [halokes.md](halokes.md), [spi-cutover-dns-tls.md](spi-cutover-dns-tls.md), [license.md](license.md), [cloudflare-migration.md](cloudflare-migration.md)

## 1. How it works

```
 app repo (GitHub)                    codelab repo (GitHub, this repo)                 VPS
 ─────────────────                    ────────────────────────────────                 ───
 push to main
   └─ notify-codelab.yml ──dispatch──▶ deploy-<site>.yml ─▶ _deploy.yml
                                          1. check out ops repo + app repo (APP_READ_TOKEN if private)
                                          2. composer install / npm build on the GitHub runner
                                          3. render .env from GitHub Secrets (scripts/render-env.sh)
                                          4. rsync app ──────────────────────────▶ releases/<sha>/
                                          5. ssh: scripts/remote/activate.sh ────▶ link shared dirs + .env,
                                                                                    migrate, cache,
                                                                                    swap `current` symlink,
                                                                                    reload php-fpm
                                          6. smoke test against the origin; failure rolls back
```

One-time per site, from your workstation: `setup-github.sh` (secrets), `provision-remote.sh` (server config), `cf-dns.sh` (DNS, Cloudflare zones only).

**Where state lives**

| What | Where | Notes |
|---|---|---|
| Server configuration templates, scripts, workflows | this repo (public) | no credentials |
| Secrets used by CI | GitHub Secrets of `dhanifudin/codelab` | `SSH_*`, `<SITE>_*`, `APP_READ_TOKEN` |
| Generated secrets, local copies | `~/.config/codelab/` (mode 700) | `<site>.env`, `cloudflare.env`, `deploy_key` |
| Deployed code, uploads, `.env` | VPS `/var/www/<domain>/{releases,shared,current}` | owned by `deploy` |
| Site settings read at deploy time | VPS `/etc/codelab/<site>.conf` | installed by provisioning |

## 2. Prerequisites

**Workstation:** `gh` (logged in as the repo owner: `gh auth status`), `ssh`, `rsync`, `curl`, `jq`, `openssl`, `git`. `shellcheck` and `actionlint` are optional (`nix run nixpkgs#shellcheck`).

**SSH alias** to the VPS in `~/.ssh/config` (the examples use `codelab`):

```
Host codelab
    HostName <vps-ip>
    User <sudo-user>          # needs passwordless sudo: provisioning runs `sudo -n`
    IdentityFile ~/.ssh/<key>
```

**VPS assumptions** (all true for the current server, Ubuntu 24.04): nginx with `sites-available`/`sites-enabled`, MariaDB or MySQL with root reachable through `sudo mysql`, certbot, rsync, ufw allowing 22/80/443, the [ondrej PHP PPA](https://launchpad.net/~ondrej/+archive/ubuntu/php) configured, and a `deploy` user. Provisioning installs the missing `php<ver>-*` packages, adds a swapfile when none exists, and never touches other sites.

**Accounts:** a GitHub account that owns both repos, and for Cloudflare-fronted domains a Cloudflare account with the zone ([cloudflare-migration.md](cloudflare-migration.md)).

## 3. Add a site (checklist)

Pick the DNS situation first, because it decides the TLS mode and the order of the last steps:

| Situation | `TLS=` | DNS | Order |
|---|---|---|---|
| Zone on Cloudflare that we control (`halokes.com`, `dhanifudin.com`) | `letsencrypt-cloudflare` (DNS-01, wildcards allowed) | `scripts/cf-dns.sh` | provision, verify against the origin, **then** DNS |
| Zone controlled by someone else (`polinema.ac.id`) | `letsencrypt-webroot` (HTTP-01) | they point the A record at the VPS | provision, deploy, ask for the record, provision **again** to get the certificate |
| No TLS yet | `none` | any | HTTP only |

### 3.1 Create the site directory

`sites/<site>/` with the files described in [site-config-reference.md](site-config-reference.md). Copy the closest existing site (`halokes` for a Laravel app on Cloudflare, `spi` for a Laravel app on foreign DNS, `license` for a Go service) and change `site.conf`, `nginx*.conf`, `env.template`, `shared-paths.txt`, `rsync-exclude.txt`, and `app-dispatch.yml`. Add `.github/workflows/deploy-<site>.yml` (copy `deploy-halokes.yml`, change `site:` and the dispatch type). Render the templates locally before committing:

```bash
bash -n provision/*.sh scripts/*.sh scripts/remote/*.sh
nix run nixpkgs#actionlint
```

Commit and push; provisioning copies the repo from your working tree, CI uses what is on GitHub.

### 3.2 Create the credentials

Follow [tokens.md](tokens.md) for the click paths. In short:

1. Private app repo: add it to the fine-grained `APP_READ_TOKEN` (Contents: read).
2. Cloudflare sites: a **dns-admin** token (`CF_API_TOKEN`, local only) and a separate **certbot** token (`CF_CERTBOT_TOKEN`).
3. Run the wizard in a normal terminal so it can prompt and hide input:

```bash
scripts/setup-github.sh <site> codelab
```

It checks the repo, creates or reuses the deploy key (`deploy.pub`, commit it once), pins the VPS host key, generates `<SITE>_APP_KEY`, `<SITE>_DB_PASSWORD` and the first admin password into `~/.config/codelab/<site>.env`, and sets the matching GitHub secrets. When you cannot give it a terminal, pass the answers as environment variables (listed in the script header), for example:

```bash
CONFIRM_FINGERPRINT=SHA256:... <SITE>_ADMIN_NAME=... <SITE>_ADMIN_EMAIL=... scripts/setup-github.sh <site> codelab
```

Verify the fingerprint yourself first: `ssh codelab 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'` must match what the wizard prints.

### 3.3 Provision the server

```bash
scripts/provision-remote.sh codelab <site>      # run it twice
```

It syncs the repo to `~/codelab` on the VPS and runs `provision/provision.sh <site>` with sudo. Secrets (database password, certbot token) travel over ssh stdin, never in arguments. Steps, in order: `10-swap`, `20-php`, `25-tls`, `26-cloudflare-ips`, `30-site` (directories, fpm pool, nginx vhost, sudoers, deploy key), `35-keys` (Go sites), `40-db`, `50-monitor`. Every step logs `unchanged:`, `changed:`, `skipped:` or `pending:`. **The second run must contain no `changed:` lines**; if it does, something is not idempotent.

Normal `pending:` lines: `DNS does not point at this server yet` (foreign DNS before the record changed) and `vhost ... not installed yet` (first run only; the certificate is requested on the next run).

### 3.4 First deploy and bootstrap

For Laravel sites that use the generic seeder (`SEED_CLASS` in `site.conf`):

```bash
gh workflow run deploy-<site>.yml --repo dhanifudin/codelab -f ref=main
gh run watch --repo dhanifudin/codelab                      # pick the run
gh workflow run bootstrap.yml --repo dhanifudin/codelab -f site=<site>
```

The `site` input of `bootstrap.yml` is a fixed list in the workflow file: add the site there. `spi` has its own `spi-bootstrap-db.yml`. Bootstrap seeds reference data and creates the first admin from `<SITE>_ADMIN_*` secrets; seeders must be idempotent and must never create demo users in production.

The deploy succeeds only if the smoke test (`SMOKE_PATH`, followed through redirects, sent straight to the origin) returns 200. Otherwise `rollback.sh` points `current` back at the previous release.

### 3.5 DNS and certificate

**Cloudflare zone** (we control it):

```bash
scripts/cf-dns.sh <site> --dry-run      # reads only
scripts/cf-dns.sh <site>                # creates/updates records listed in sites/<site>/dns.records
scripts/cf-dns.sh <site>                # second run: everything unchanged
```

Do this **after** the origin serves the host. A record pointing at an origin that does not know the host answers with another site's certificate (Cloudflare shows 526 in strict mode).

**Foreign zone:** send the owner this request: *"Please set an `A` record for `<host>` to `<vps-ip>`, DNS only (no proxy). Ports 80 and 443 are open; we use Let's Encrypt, which validates over port 80."* When `dig +short <host> @1.1.1.1` shows the VPS address, run `scripts/provision-remote.sh codelab <site>` again. The certificate is issued, the vhost switches to HTTPS, then set the public URL and redeploy:

```bash
gh variable set <SITE>_APP_URL --body https://<host> --repo dhanifudin/codelab
gh workflow run deploy-<site>.yml --repo dhanifudin/codelab
```

### 3.6 Auto-deploy

Create `CODELAB_DISPATCH_TOKEN` ([tokens.md](tokens.md), section 4) and store it in the **app** repo: `gh secret set CODELAB_DISPATCH_TOKEN --repo dhanifudin/<app-repo>`. The app repo needs `.github/workflows/notify-codelab.yml` (template: `sites/<site>/app-dispatch.yml`). After that every push to `main` deploys. Merge that workflow only after the first manual deploy worked.

### 3.7 Verify

```bash
curl -sI https://<host>/<smoke-path> | head -1                       # 200, valid certificate
curl -s -o /dev/null -w '%{http_code}\n' https://<host>/.env         # 403/404
curl -s -o /dev/null -w '%{http_code}\n' http://<host>/              # 301 to https (when TLS is on)
ssh codelab 'readlink /var/www/<domain>/current; ls /var/www/<domain>/releases'
```

Log in with the admin credentials from `~/.config/codelab/<site>.env` (never paste them into chat), change the password, upload a file, deploy again, and confirm the file survived (it lives in `shared/`). Check that other sites on the VPS still answer.

Certificate renewal is automatic (`certbot.timer`). To prove it works: `ssh codelab 'sudo certbot renew --dry-run --cert-name <domain>'`. It can take ten minutes, so run it detached (`nohup ... &`) and read `/var/log/letsencrypt/letsencrypt.log`.

## 4. Operate

| Task | Command |
|---|---|
| Deploy a branch/tag/sha | `gh workflow run deploy-<site>.yml --repo dhanifudin/codelab -f ref=<ref>` |
| Roll back to the previous release | `ssh codelab 'sudo -u deploy bash -s -- <site>' < scripts/remote/rollback.sh` (database migrations are **not** reverted) |
| Re-apply server config after editing `sites/<site>` | `scripts/provision-remote.sh codelab <site>` |
| Change DNS records | edit `sites/<site>/dns.records`, `scripts/cf-dns.sh <site> --dry-run`, then apply |
| Add a school host to halokes | [halokes.md](halokes.md#adding-a-school-subdomain) |
| Rotate a token | revoke it where it was created, create a new one with the same permissions, replace the stored copy (`~/.config/codelab/*.env` or `gh secret set`), re-run provisioning if the VPS holds it (certbot token) |
| See what is deployed | `ssh codelab 'readlink /var/www/<domain>/current'` |
| Watch disk | `ssh codelab 'df -h /'` (monit only logs above 90%; each Laravel release is a few hundred MB) |

Releases kept per site: `KEEP_RELEASES` in `site.conf` (older ones are deleted at each deploy; the active one never is).

## 5. Remove a site

1. Delete `sites/<site>`, its workflow(s) and its DNS records; push.
2. On the VPS: `sudo rm /etc/nginx/sites-enabled/<domain>.conf /etc/nginx/sites-available/<domain>.conf /etc/php/<ver>/fpm/pool.d/<pool>.conf /etc/sudoers.d/codelab-<site> /etc/codelab/<site>.*`, then `sudo nginx -t && sudo systemctl reload nginx php<ver>-fpm`.
3. Optionally drop the database and user (`sudo mysql -e "DROP DATABASE <db>; DROP USER '<db>'@'localhost';"`) and `rm -r /var/www/<domain>` after taking a backup.
4. Delete the `<SITE>_*` GitHub secrets and the certificate (`sudo certbot delete --cert-name <domain>`).

## 6. Worked examples

| | halokes | spi | license |
|---|---|---|---|
| App | Laravel 12 + Vite | Laravel 9 | Go service (`KIND=go`) |
| PHP | 8.4 (shared master) | 8.4 | none |
| DNS | Cloudflare, we control | Polinema IT | Cloudflare, we control |
| TLS | `letsencrypt-cloudflare`, wildcard | `letsencrypt-webroot` | `letsencrypt-cloudflare` |
| Build | composer + `npm run build` | composer only (assets committed) | Go binary |
| Seeding | `ProductionSeeder` via `bootstrap.yml` | `bootstrap-spi.sh` via `spi-bootstrap-db.yml` | migrations run at service start |
| Extras | tenant hosts (`TENANTS`) | empty user-data folders | systemd unit, signing keys |
