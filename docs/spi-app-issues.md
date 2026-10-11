# spi.polinema.ac.id app: findings

Source: `dhanifudin/spi.polinema.ac.id` at `main` (Laravel 9.52, 3 commits, student-written). These were found by reading the code, not by running it. The legacy app is deployed with deploy-level mitigations only; code fixes belong in the v2 rewrite (see `spi-v2-decisions.md`).

## Mitigated at deploy level

| Issue | Mitigation |
|---|---|
| `/register` lets anyone choose `id_level` (Super Admin included) | nginx returns 404 for `/register` |
| Debug scripts, `pelaporan` SQLite file, `coverage.xml`, `public/coverage-report/` in the repo | excluded from releases (`rsync-exclude.txt`), blocked in nginx |
| `APP_DEBUG=true` in `.env.example` | production `.env` sets `false` |
| Uploads in `public/` could execute as PHP, SVG can carry script | only `index.php` executes; upload dirs get `Content-Security-Policy: sandbox` |
| Seeders create real staff accounts with password `123456` and Super Admin `test`/`123` | bootstrap workflow seeds reference data only, creates one admin from secrets |
| Uploads lost on redeploy | upload dirs and `storage/` are shared across releases |

## Not mitigated (still present in the deployed legacy app)

1. Almost no authorization beyond `auth`: any logged-in user can approve/delete users, change another user's password (`UserController.php:161,198,240,249`) and act on posts, risks and letters by id.
2. Mass assignment: `$petas->update($request->all())` (`PetaController.php:548`), `$uraian->update($request->all())` (`MRController.php:107`); `User::$fillable` includes `id_level` and `is_approved`.
3. Weak upload validation: `TemplateDokumenController.php:61,82` (no type check), `KelolaController.php:184` (original filename kept).
4. Unauthenticated routes: `/posts/{id}/comment/{type}` (GET, POST), `/get-rtm/{postId}`, `/template`, `/feedback_web`.
5. No login throttling; registration and profile passwords have weak minimum length.
6. 48 unescaped `{!! !!}` outputs in Blade views.
7. Raw request logging at `ManajemenRisikoController.php:787`; a hard-coded developer email in dead code at `:1382`.
8. 38 tables, foreign keys mostly not enforced; unit names joined by string (`PetaController.php:56`); three tables have no migration (`landing_page_settings`, `kualitas`, `aktivitas`); seeders hard-code ids.

Operational advice until v2: restrict the site to trusted users (for example HTTP basic auth at nginx) if real audit data is entered.
