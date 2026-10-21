# codelab

Ops repository for the sites hosted on the "codelab" VPS (ssh alias `codelab`, Ubuntu 24.04, nginx + PHP-FPM, local MariaDB, no Docker). It holds server and deploy configuration only. Application code stays in each app's own repository.

| Site | App repo | Status |
|---|---|---|
| `halokes.com` | `dhanifudin/halokes` (Laravel 12, private) | active; DNS moving to Cloudflare, see `docs/halokes.md` |
| `license.dhanifudin.com` | `dhanifudin/license.dhanifudin.com` (Go, private) | `KIND=go` binary site; see `docs/license.md` |
| `spi.polinema.ac.id` | [dhanifudin/spi.polinema.ac.id](https://github.com/dhanifudin/spi.polinema.ac.id) (Laravel 9) | first deploy in progress; HTTPS follows once Polinema IT points DNS here (`docs/spi-cutover-dns-tls.md`) |

## Layout

```
sites/<site>/        per-site config: site.conf, nginx.conf, php-fpm-pool.conf, env.template, dns.records, ...
deploy.pub           public half of the repo-wide deploy key
provision/           idempotent root scripts run on the VPS (swap, PHP, TLS, Cloudflare IPs, vhost + pool, sudoers, DB, monit)
scripts/             local helpers: setup-github.sh, provision-remote.sh, render-env.sh, cf-dns.sh
scripts/remote/      run on the VPS by CI: activate.sh, rollback.sh, bootstrap.sh, bootstrap-spi.sh
.github/workflows/   _deploy.yml (reusable), deploy-<site>.yml, bootstrap.yml, spi-bootstrap-db.yml
docs/                cutover runbook, findings about the spi app, v2 decisions
```

Adding a site means adding `sites/<site>/` with the same files. `KIND=go` sites (see `docs/license.md`) have a `systemd.service` instead of `php-fpm-pool.conf`, and no PHP, Composer or artisan steps. `provision/*.sh` and `activate.sh` are site-agnostic and read `site.conf`.

## First-time setup of a site

1. DNS: for Cloudflare-fronted sites follow `docs/cloudflare-migration.md` (`scripts/cf-dns.sh <site>`).
2. `scripts/setup-github.sh <site> codelab` creates the private repo, the deploy SSH key (`deploy.pub`) and the GitHub secrets. Generated passwords are kept in `~/.config/codelab/<site>.env`, outside git. Commit and push `deploy.pub`.
3. `scripts/provision-remote.sh codelab <site>` configures the VPS. It is safe to run again; unchanged items log `unchanged:` and nothing reloads.
4. Run the **Deploy <site>** workflow (Actions, Run workflow), then **Bootstrap site data** once.
5. Add the dispatch token and workflow to the app repo so every push to its `main` deploys (`sites/<site>/app-dispatch.yml`; the wizard prints the token steps).

Where each token comes from: `docs/tokens.md`. Per-site runbooks: `docs/halokes.md`; spi is described in `docs/spi-app-issues.md` and `docs/spi-cutover-dns-tls.md`.

## Deploy model

Push to the app's `main` sends `repository_dispatch` (`deploy-<site>`) here. The workflow builds on the GitHub runner (composer, plus npm/Vite when the site sets `NODE_BUILD=1`), rsyncs to `releases/<sha>`, links shared paths (`storage/` and the upload directories under `public/`) and `.env`, runs `migrate --force`, caches config/routes/views, then atomically repoints `current` and reloads that site's php-fpm. The two newest releases are kept. A failed smoke test (`SMOKE_PATH` from `site.conf` must return 200, checked directly against the origin) rolls back automatically.

For `KIND=go` sites the runner runs `go build` instead, the release is the binary, and the switch restarts the site's systemd unit instead of reloading fpm.

Manual rollback: `ssh codelab 'sudo -u deploy bash -s -- <site>' < scripts/remote/rollback.sh`. Migrations are not reverted.

## What is and isn't in this repo

Configuration only: nginx and PHP-FPM templates, provisioning and deploy scripts, workflows, runbooks. No credentials. Secrets live in this repo's GitHub Secrets and in `~/.config/codelab/` on the operator's machine; `deploy.pub` is the public half of the deploy key. To report a security problem, open a private security advisory on this repository instead of a public issue.

## Secrets

All secrets live in GitHub Secrets of this repo (plus `~/.config/codelab/` locally). Never commit `.env` files. See `scripts/setup-github.sh` for the full list.
