# spi.polinema.ac.id: deploy-level mitigations

Source: `dhanifudin/spi.polinema.ac.id` at `main` (Laravel 9.52). The legacy app is deployed with deploy-level mitigations only; code fixes belong in the v2 rewrite (see `spi-v2-decisions.md`).

## Mitigated at deploy level

| Issue | Mitigation |
|---|---|
| Open self-registration | nginx returns 404 for `/register`; accounts are created by an admin |
| Debug scripts, `pelaporan` SQLite file, `coverage.xml`, `public/coverage-report/` in the repo | excluded from releases (`rsync-exclude.txt`), blocked in nginx |
| `APP_DEBUG=true` in `.env.example` | production `.env` sets `false` |
| Uploads written under `public/` | only `index.php` executes as PHP; upload dirs get `Content-Security-Policy: sandbox` |
| Demo seeders ship default accounts | bootstrap workflow seeds reference data only, creates one admin from secrets |
| Uploads lost on redeploy | upload dirs and `storage/` are shared across releases |
