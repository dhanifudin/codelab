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

Found by a pre-deploy review; verified on PHP 8.3 and 8.4 + MariaDB 10.11 (production runs 8.4, already on the VPS; Laravel 9 does not officially support it, and the checks showed no errors or deprecation noise) (migrate, the bootstrap seeder list, `config:cache`/`route:cache`/`view:cache`, and HTTP checks per role).

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

Added after go-live (2026-11-12, Manajemen User):

| Issue | Fix |
|---|---|
| The user list showed no email and its search ignored it; the login says email but the field read "Username"; two accounts could share an email | Email and Status columns, search by name, NIP or email, label `Email / Username`; unique index on `users.email` (the migration refuses with a list of duplicates instead of failing blindly) |
| No way to disable an account: the only options were Hapus, which also deletes the user's comments, MR answers and letters, and Tolak, which deleted any account | `users.is_active`: Nonaktifkan / Aktifkan in the list. A disabled user cannot log in and an open session ends on the next request (`EnsureUserIsActive`); disabled users are hidden from auditor, PIC and member dropdowns; nobody can disable themselves, and the last active Super Admin cannot be disabled, deleted or demoted. Hapus is Super Admin only; Tolak only works on a registration that was never approved. `spi:import-staff` never re-enables a disabled account |
| The user pages overflowed on phones (page 771px wide at 375px), and on every page the sidebar stayed open over the content because `public/js/scripts.js` threw on `Chart.defaults.global` (the layout loads an unpinned Chart.js from a CDN) | compact rows below 992px and columns above; script guarded; viewport allows zoom; pagination wraps. Checked in headless Chromium at 375, 768, 1024, 1280 and 1440px |

Deploy note: the email index migration stops if duplicate emails exist; fix them first (`select lower(email), count(*) from users group by 1 having count(*) > 1`).

## Known and left for v2

- No per-record/unit checks: any logged-in user with a role that can open a post, peta or risk can read or act on others' records (IDOR). Workflow actions on posts and peta still only check the role.
- `GET /logout` (CSRF logout), CKEditor 4 and other CDN assets are end-of-life or unpinned.
- Routes with no controller method or view (they return a 500): `posts.update`, `users.edit`/`update`, `dokumens.edit`/`update`, `unit-kerja.create`/`show`/`edit`, `petas.show`, `MR.create`/`show`, `/rtm/search` (`post.RTM`), `posts.comment` (`comments.create`), `MR.edit` (`elements.edit`), and the unused `manajemen-risiko/detail-unit/{id}/kegiatan/{id}` (`partials.detail_risiko_kegiatan`).
- Sidebar entry for `/jenis-template`, `/entitas`, `/bobot`, `/verif`, `/kesimpulan` and `/kegiatan` does not exist; they are reachable by URL only.
| Sample documents and signatures committed in the app repo | user-data upload folders start empty in production (`shared-paths.txt` flag `empty`, excluded from the release) |
