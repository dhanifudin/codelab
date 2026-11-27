# sirw: rw05tanjungrejo.or.id

Laravel 9 on PHP 8.4, local MariaDB, behind Cloudflare (zone we control). Configuration is in `sites/sirw/`. Follow [runbook.md](runbook.md); this page lists what is specific to this site. It starts with an empty database.

## Before the first deploy

1. Cloudflare R2: create a **public** bucket with the custom domain `files.rw05tanjungrejo.or.id`, a **private** bucket without any public access, and a separate **backup** bucket. Create one API token for the two upload buckets and another for the backup bucket (Object Read & Write, limited to those buckets).
2. Cloudflare Turnstile: create a widget for the domain.
3. Email: choose an SMTP provider and add its SPF and DKIM records to the zone. This can wait: without `SIRW_MAIL_HOST` the site deploys and sends nothing, so new accounts cannot confirm their address and password reset does not work.
4. Backup key, on your workstation: `age-keygen -o sirw-backup.key`. Keep that file offline and safe; without it no backup can be read. Only the public key (`age1...`) goes into the configuration.
5. Allow the app repository for `APP_READ_TOKEN`.

## Secrets and variables

`scripts/setup-github.sh sirw codelab` creates the app key, database password and first admin password. Use the owner's address as `SIRW_ADMIN_EMAIL`.

Then set the rest on this repository (`gh secret set NAME --repo dhanifudin/codelab`):

| Name | Kind | Required |
|---|---|---|
| `SIRW_MAIL_HOST`, `SIRW_MAIL_USERNAME`, `SIRW_MAIL_PASSWORD` | secret | no; once the host is set, all three. Deploy again after setting them |
| `SIRW_MAIL_PORT` (587), `SIRW_MAIL_ENCRYPTION` (tls), `SIRW_MAIL_FROM` | variable | no |
| `SIRW_TURNSTILE_SITE_KEY`, `SIRW_TURNSTILE_SECRET_KEY` | secret | recommended |
| `SIRW_FILES_ACCOUNT_ID`, `SIRW_FILES_KEY_ID`, `SIRW_FILES_SECRET`, `SIRW_FILES_PUBLIC_BUCKET`, `SIRW_FILES_PRIVATE_BUCKET`, `SIRW_FILES_PUBLIC_URL` (`https://files.rw05tanjungrejo.or.id`) | secret | only with `SIRW_FILES_DISK=r2` |
| `SIRW_FILES_DISK` | variable | no; `local` (default, uploads stay on the server) or `r2` |
| `SIRW_LETTERS_ENABLED` | variable | leave unset (off) until the app is ready for it |

For the backup add these lines to `~/.config/codelab/sirw.env`:

```
BACKUP_R2_ACCOUNT_ID=
BACKUP_R2_ACCESS_KEY_ID=
BACKUP_R2_SECRET_ACCESS_KEY=
BACKUP_R2_BUCKET=
BACKUP_AGE_RECIPIENT=age1...
```

**Decide about R2 before the first real upload**, and set `SIRW_FILES_DISK=r2` before deploying if you want it. The app's `uploads:migrate-r2` command only handles files from the old, pre-deployment layout; it does **not** move files uploaded while on `local`. Switching later means copying them to the buckets under the same names first (`shared/storage/app/public/{galeri,agenda,organisasi,potensi}` to the public bucket, `shared/storage/app/{ttd,surat,lampiran}` to the private one), then changing the variable, deploying, and copying once more.

## First deploy

```bash
scripts/provision-remote.sh codelab sirw        # twice; the second run shows no "changed:"
gh workflow run deploy-sirw.yml --repo dhanifudin/codelab -f ref=main
gh workflow run bootstrap.yml --repo dhanifudin/codelab -f site=sirw
scripts/cf-dns.sh sirw --dry-run && scripts/cf-dns.sh sirw
```

The bootstrap creates the super-admin, roles and permissions, aid categories, vaccines and vitamins. It is safe to run again and never changes an existing password. Sign in, then change the password.

Check afterwards:

- `https://rw05tanjungrejo.or.id/login` answers 200, `/.env` does not.
- Uploading a gallery image shows it on the public page, and it survives another deploy.
- With mail configured, a password reset mail arrives.
- `ssh codelab 'sudo systemctl start sirw-backup && sudo journalctl -u sirw-backup -n 5'`, then do a test restore (below).

Growth reference files for the child health ranking: copy the four WHO CSV files to `/var/www/rw05tanjungrejo.or.id/shared/storage/app/file_growth/` (owner `deploy`), then run `php8.4 artisan who:import-lms` in `current` as `deploy`.

Add `sites/sirw/app-dispatch.yml` to the app repository (runbook 3.6) only after a manual deploy has worked.

Nothing in the application needs cron or a queue worker.

## Backups

Nightly at about 02:30 (Asia/Jakarta), `sirw-backup.timer`: `db-<time>.sql.gz.age` and `storage-<time>.tar.gz.age` under `sirw/` in the backup bucket, kept 30 days. Files in the R2 upload buckets are **not** included, so with `SIRW_FILES_DISK=r2` uploads have no backup from this job.

Check: `ssh codelab 'systemctl list-timers sirw-backup.timer; sudo journalctl -u sirw-backup -n 20'`. Nothing sends an alert when a backup fails, so look from time to time.

Restore: download the two files from the bucket and decrypt them on a machine that has the private key.

```bash
age -d -i sirw-backup.key db-<time>.sql.gz.age | gunzip > sirw.sql
age -d -i sirw-backup.key storage-<time>.tar.gz.age > storage.tar.gz
scp sirw.sql storage.tar.gz codelab:
```

For a test restore, load the dump into a throwaway database and compare a few row counts, then drop it:

```bash
sudo mysql -e 'CREATE DATABASE sirw_restore'
sudo mysql sirw_restore < sirw.sql
sudo mysql -e 'SELECT COUNT(*) FROM sirw_restore.users; DROP DATABASE sirw_restore'
```

For a real restore (this overwrites current data):

```bash
cd /var/www/rw05tanjungrejo.or.id/current && sudo -u deploy php8.4 artisan down
sudo mysql sirw < ~/sirw.sql
sudo tar -C /var/www/rw05tanjungrejo.or.id/shared -xzf ~/storage.tar.gz
sudo chown -R deploy:www-data /var/www/rw05tanjungrejo.or.id/shared/storage
sudo -u deploy php8.4 artisan up
```

The files contain personal data. Delete the decrypted copies, on both machines, after use.
