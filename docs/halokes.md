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

## Adding a school subdomain

Example: Aboe Bakar Soemijati at `abs.halokes.com`. The certificate is a wildcard (`*.halokes.com`), so no certificate change is needed.

1. In `sites/halokes/site.conf` add the host to `SERVER_NAMES` and a `host:KODE` entry to `TENANTS` (KODE is the school's `kode_yayasan` in the app, e.g. `abs.halokes.com:ABS`).
2. In `sites/halokes/dns.records` add `A <label> 194.127.193.198 true auto`.
3. Provision first, DNS last (a DNS record that points at an origin which does not yet serve the host answers with another site's certificate and Cloudflare shows a 526):
   `scripts/provision-remote.sh codelab halokes`, check `curl --resolve abs.halokes.com:443:194.127.193.198 https://abs.halokes.com/up`, then `scripts/cf-dns.sh halokes`.
4. Onboard the school in the app (below).

Until the app has host-based tenancy, nginx redirects `/` and `/login` on a school host to that yayasan's portal (`/y/KODE`, `/y/KODE/login`) on the same host. Other hosts are not routed to the app unless listed in `SERVER_NAMES`, even though the certificate is a wildcard.

### Onboarding a school in the app

The school's pages return 404 until its yayasan exists.

1. Owner, `/owner/yayasans/create`: set `nama_yayasan`, **`kode_yayasan` = the KODE from `TENANTS`**, `status` = aktif.
2. `/superadmin/users`: create the school's `super_admin` (`yayasan_id` = the new yayasan).
3. Switch to that yayasan and create the school at `/superadmin/schools/create`. Check that its `yayasan_id` is the new yayasan, not 1 (the app silently falls back to 1).
4. `/superadmin/schools/{id}/modules`: enable modules, then create admin, kepsek and guru users.
5. Optional: insert a `domains` row (`school_id`, the host, `is_verified=1`). It only matters for the app's `/check-domain` endpoint.

## Operations

- **Deploy:** push to the app's `main` (dispatch) or run **Deploy halokes** manually with a ref.
- **Roll back:** `ssh codelab 'sudo -u deploy bash -s -- halokes' < scripts/remote/rollback.sh`. Migrations are not reverted.
- **Disk:** the VPS root disk is tight (about 80% used). Each release is a few hundred MB with `vendor/` and `public/build`; two are kept. Uploads grow `shared/storage`; plan R2 before it fills. monit logs a warning above 90% to `/var/log/monit.log`.

## Known app-side requirements

- `database/schema/mysql-schema.sql` must exist, because the repo has no `create_*` migrations.
- `ProductionSeeder` must be idempotent and read `HALOKES_ADMIN_NAME/EMAIL/PASSWORD` from the environment.
- `MasterFreshDatabaseSeeder` truncates every table. It must never run in production.
