# spi v2 (rewrite): decisions so far

Context: the Laravel 9 app is end-of-life and needs structural security work. It is deployed as a stopgap with the mitigations in `spi-app-issues.md`. The rewrite is a separate project; this file only records what was decided so far.

| Topic | Decision |
|---|---|
| Location | branch `v2` in `dhanifudin/spi.polinema.ac.id`, merged to `main` at cutover (the same dispatch workflow then deploys it) |
| Stack | latest supported Laravel, Filament v4 admin panel, public landing page in plain Blade |
| PHP | 8.4 or 8.5; new fpm pool on the existing `php8.4-fpm`/`php8.5-fpm` already on the VPS (the legacy app already runs in its own pool on `php8.4-fpm`) |
| Authorization | policies on every Filament resource; roles from the old `levels` table (Super Admin, Admin, Ketua, Anggota, Auditee, Sekretaris) |
| Registration | admin-created accounts only (or approval-gated with a fixed default role) |
| Uploads | Cloudflare R2 via `league/flysystem-aws-s3-v3`. Landing images: public bucket/path. Documents, signatures, certificates, letters: private bucket, served through a controller with a policy check plus short-lived `temporaryUrl()`. |
| Upload validation | allow-list of mime and extension, random server-side filenames, no SVG for signatures |
| Data | reference data (levels, menus, unit kerja, questionnaire) carried over from the old seeders; no demo users |
| Module inventory | auth/RBAC, unit kerja, kegiatan, audit tasks (reviu workflow with approvals and Word/PDF output), tindak lanjut, RTM, peta risiko (Excel import/export), manajemen risiko (auditor/auditee workflow, PDF), tata kelola (maturity questionnaire), berita acara, surat, landing page settings |
| Size of legacy app | 31 controllers (about 10.8k LOC), 36 models, 107 views, 53 migrations, about 280 routes |

Needed from this repo when v2 lands: R2 credentials as GitHub Secrets and `env.template` entries, `shared-paths.txt` trimmed (uploads no longer on disk), a new `PHP_VERSION` in `site.conf`.
