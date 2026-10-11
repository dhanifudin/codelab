# halokes.com runbook

App: `dhanifudin/halokes` (private), Laravel 12, Blade plus a React landing page built with Vite. Multi-tenant by Host header (`domains` table). Only `halokes.com` and `www.halokes.com` are served for now.

| Item | Value |
|---|---|
| Server | ssh alias `codelab` (194.127.193.198), user `deploy` owns the release tree |
| Web root | `/var/www/halokes.com/current/public` (symlink to `releases/<sha>`) |
| PHP | 8.4, dedicated pool `halokes`, socket `/run/php/php8.4-fpm-halokes.sock` (shares the fpm master with the other sites) |
| Database | MariaDB `halokes`, user `halokes`@localhost |
| Persistent data | `shared/storage` (uploads, logs, sessions are in the DB) |
| Health check | `GET /up` |

## First run, in order

1. Cloudflare zone, tokens, records, nameservers: `docs/cloudflare-migration.md`.
2. `scripts/setup-github.sh halokes codelab` (tokens: `docs/tokens.md`; non-interactive variables are in the script header). Commit and push `deploy.pub`.
3. `scripts/provision-remote.sh codelab halokes`. Run it twice: the second run must log only `unchanged:` and `skipped:` lines.
4. App PRs merged in `dhanifudin/halokes`: schema baseline, `ProductionSeeder`, cleanup, `notify-codelab.yml`.
5. Actions, **Deploy halokes**, Run workflow. Then Actions, **Bootstrap site data**, site `halokes`.

## Operations

- **Deploy:** push to the app's `main` (dispatch) or run **Deploy halokes** manually with a ref.
- **Roll back:** `ssh codelab 'sudo -u deploy bash -s -- halokes' < scripts/remote/rollback.sh`. Migrations are not reverted.
- **Disk:** the VPS root disk is tight (about 80% used). Each release is a few hundred MB with `vendor/` and `public/build`; two are kept. Uploads grow `shared/storage`; plan R2 before it fills. monit logs a warning above 90% to `/var/log/monit.log`.

## Known app-side requirements

- `database/schema/mysql-schema.sql` must exist, because the repo has no `create_*` migrations.
- `ProductionSeeder` must be idempotent and read `HALOKES_ADMIN_NAME/EMAIL/PASSWORD` from the environment.
- `MasterFreshDatabaseSeeder` truncates every table. It must never run in production.
