# codelab

Ops repository for the sites hosted on the "codelab" VPS (ssh alias `codelab`, Ubuntu 24.04, nginx + PHP-FPM, local MariaDB, no Docker). It holds server and deploy configuration only. Application code stays in each app's own repository.

| Site | App repo | Status |
|---|---|---|
| `spi.polinema.ac.id` | [dhanifudin/spi.polinema.ac.id](https://github.com/dhanifudin/spi.polinema.ac.id) (Laravel 9) | HTTP only, DNS pending |
| `halokes.com` | not available yet | postponed |

## Layout

```
sites/<site>/        per-site config: site.conf, nginx.conf, php-fpm-pool.conf, env.template, ...
provision/           idempotent root scripts run on the VPS (swap, PHP, vhost + pool, sudoers, DB)
scripts/             local helpers: setup-github.sh, provision-remote.sh, render-env.sh
scripts/remote/      run on the VPS by CI: activate.sh, rollback.sh, bootstrap-spi.sh
.github/workflows/   deploy-spi.yml, spi-bootstrap-db.yml
docs/                cutover runbook, findings about the spi app, v2 decisions
```

Adding a site means adding `sites/<site>/` with the same files. `provision/*.sh` and `activate.sh` are site-agnostic and read `site.conf`.

## First-time setup (spi)

1. `scripts/setup-github.sh codelab` creates the private repo, a deploy SSH key (`sites/spi/deploy.pub`), and all GitHub secrets. Generated passwords are kept in `~/.config/codelab/spi.env`, outside git.
2. Commit and push `sites/spi/deploy.pub`.
3. `scripts/provision-remote.sh codelab spi` configures the VPS. It is safe to run again; unchanged items log `unchanged:` and nothing reloads.
4. Run the **Deploy spi** workflow (Actions, Run workflow), then **Bootstrap spi data** once.
5. Create the `CODELAB_DISPATCH_TOKEN` PAT and copy `sites/spi/app-dispatch.yml` into the app repo so every push to its `main` deploys. The wizard prints the exact steps.

## Deploy model

Push to the app's `main` sends `repository_dispatch` (`deploy-spi`) here. The workflow builds on the GitHub runner (composer, no npm: the app commits its compiled assets), rsyncs to `releases/<sha>`, links shared paths (`storage/` and the upload directories under `public/`) and `.env`, runs `migrate --force`, caches config/routes/views, then atomically repoints `current` and reloads `php8.3-fpm`. The two newest releases are kept. A failed smoke test (`GET /login` must return 200) rolls back automatically.

Manual rollback: `ssh codelab sudo -u deploy bash -s -- spi < scripts/remote/rollback.sh`. Migrations are not reverted.

## Secrets

All secrets live in GitHub Secrets of this repo (plus `~/.config/codelab/` locally). Never commit `.env` files. See `scripts/setup-github.sh` for the full list.

## Testing before DNS

Add `194.127.193.198 spi.polinema.ac.id` to your `/etc/hosts`, then open `http://spi.polinema.ac.id`. See `docs/cutover-dns-tls.md` for the DNS and HTTPS cutover.
