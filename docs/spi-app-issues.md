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
| Audit-scan upload mail hardcoded to a developer's Gmail | recipient now read from `MAIL_SCAN_AUDIT_TO` (secret `SPI_MAIL_SCAN_AUDIT_TO`); empty means no mail is sent |

## Fixed in the app before the first deploy

Found by a pre-deploy review; verified on PHP 8.3 + MariaDB 10.11 (migrate, the bootstrap seeder list, `config:cache`/`route:cache`/`view:cache`, and HTTP checks per role).

| Issue | Fix |
|---|---|
| Anyone could register as Super Admin and was logged in at once | registration forces the Auditee level, `is_approved=false`, no auto-login; login refuses unapproved accounts |
| Any logged-in user could change any user's password or level | admin routes carry a `level:` middleware (`EnsureUserLevel`); profile edits are owner-only (admins excluded for Super Admin accounts); only a Super Admin can grant or touch level 1 |
| Admin areas (users, letters, berita acara, maturity rating, templates, risk admin, landing settings) only required login | gated by level, derived from the seeded menu permissions |
| Mass assignment in `PetaController::update` and `MRController::uraianUpdate` | only the form's own fields are accepted |
| Stored XSS in letter bodies (`{!! isi_surat !!}`) | `App\Support\HtmlSanitizer` on save and on render |
| Uploads named from the client's extension/filename; SVG allowed | `UploadedFile::safeExtension()` allowlist; random names; SVG removed |
| `route:cache` failed (duplicate route names); `landing_page_settings` had no migration; Linux case mismatches; `dd()` calls; `Pdo\Mysql` (PHP 8.4 only) in `config/database.php` | fixed |
| Login had no brute-force protection | 5 failed attempts per username+IP per minute (failures only, because users share the campus IP) |
| Admin-created users could not reach `/dashboard` (`email_verified_at` not fillable) | set explicitly |
| Debug scripts, `coverage.xml`, `public/coverage-report/`, `pelaporan` SQLite, `.DS_Store` tracked in git | removed from the tree and ignored (still in git history; the repo is private) |

## Known and left for v2

- No per-record/unit checks: any logged-in user with a role that can open a post, peta or risk can read or act on others' records (IDOR). Workflow actions on posts and peta still only check the role.
- `GET /logout` (CSRF logout), CKEditor 4 and other CDN assets are end-of-life or unpinned.
- Routes with no controller method or view (they return a 500): `posts.update`, `users.edit`/`update`, `dokumens.edit`/`update`, `unit-kerja.create`/`show`/`edit`, `petas.show`, `MR.create`/`show`, `/rtm/search` (`post.RTM`), `posts.comment` (`comments.create`), `MR.edit` (`elements.edit`), and the unused `manajemen-risiko/detail-unit/{id}/kegiatan/{id}` (`partials.detail_risiko_kegiatan`).
- Sidebar entry for `/jenis-template`, `/entitas`, `/bobot`, `/verif`, `/kesimpulan` and `/kegiatan` does not exist; they are reachable by URL only.
