# halokes demo (yayasan Aboe Bakar Soemijati)

A complete dataset for the yayasan with kode `ABS`, built to exercise every implemented halokes feature on:

- **https://halokes.com**: platform landing, public registration form, owner area.
- **https://abs.halokes.com**: the ABS tenant (landing, login portal, every role, PPDB form).

The data comes from `DemoSeeder` in the app repo and is created, refreshed or removed by the workflow **Seed demo (halokes)**. Everything it creates is tagged (emails end in `@demo.halokes.com`, NIKs start with `9999`, files live under `demo/abs/`), so it can be removed without touching real data.

## Current state (seeded 2026-11-04)

| Item | State |
|---|---|
| App release | `main` at `ba103145` in `dhanifudin/halokes`: PRs #6 (modules), #7 (`syncAll` fix), #8 and #10 (`DemoSeeder`), #9 (tenant login hints) and #11 (central login demo owner) are all deployed |
| Demo data | seeded and complete: 2 schools, 3 classes, 41 children, 31 parents, 8 staff accounts, 12 announcements, 21 materi, 96 journal entries, 32 rapor, 8 archived rapor, 3 registrations |
| Demo platform owner | **removed** on 2026-11-04 after the demo (only that account, by exact email, role and name; sessions cleared). Re-create it with **Seed demo** `include_owner = true` |
| Quick-login hints | **on** (`HALOKES_DEMO_LOGIN_HINTS` is set in this repo). The tenant login page lists the five role accounts; the central login page offers the demo owner only while that account exists (not now). Both buttons fill the **email only**: `HALOKES_DEMO_LOGIN_PASSWORD` is not set, so no password is on any page |
| Secrets in use | `HALOKES_DEMO_PASSWORD` (shared password of the tenant accounts), `HALOKES_DEMO_OWNER_PASSWORD` (demo owner, separate), `HALOKES_DEMO_LOGIN_HINTS` (flag; a repository variable works too) |
| Last verification | `scripts/demo-smoke.sh` with `EXPECT_HINTS=1`, `OWNER_EMAIL`/`OWNER_PASSWORD` after the owner was removed: **44 of 44 checks passed** (with the demo owner present it was 47 of 47) (every role logs in and opens its pages; both owners reach the owner area; no password appears in the central login page) |
| Your real owner | `dhanifudin@gmail.com`, untouched and never shown |

## Setup (once)

1. The app has the `DemoSeeder` and the related fixes deployed (halokes PRs #6 to #11, see *Current state*). Check that `DemoSeeder.php` is really on `main` before running the workflow: a stacked PR merged into its base branch instead of `main` once left it out (see `troubleshooting.md`).
2. Choose the shared password of the demo accounts (at least 8 characters) and store it **as a GitHub secret** in this repo, plus locally for the smoke test:
   ```bash
   gh secret set HALOKES_DEMO_PASSWORD --repo dhanifudin/codelab
   printf 'HALOKES_DEMO_PASSWORD=%s\n' 'the-password' >> ~/.config/codelab/halokes.env   # mode 600 already
   ```
3. Actions, **Seed demo (halokes)**, Run workflow, `action = seed`, `reset_passwords = true`. Leave `include_owner` off unless you need the demo platform owner (below).
4. Check it: `scripts/demo-smoke.sh` (logs in as every demo role, requests the pages, reports `N/N checks passed`).

## Operate

| Task | How |
|---|---|
| Refresh dates before a presentation | run **Seed demo** again (`seed`); announcements, attendance, journals and growth records move to the current date |
| Change the demo password | update `HALOKES_DEMO_PASSWORD`, run **Seed demo** with `reset_passwords = true` |
| Remove all demo data | **Seed demo** with `action = purge`: demo users, schools, children, rapor, files and demo registrations go; the yayasan, the owner, modules and the global semester/template stay |
| Demo platform owner | **Seed demo** with `include_owner = true` (needs the secret `HALOKES_DEMO_OWNER_PASSWORD`). `purge` removes it **together with all other demo data**. To remove only the owner, delete that one row on the server (guarded by exact email, role and name) and its sessions: `sudo mysql halokes -e "delete s from sessions s join users u on u.id=s.user_id where u.email='owner@yayasan.com' and u.role='owner' and u.name='Owner Demo'; delete from users where email='owner@yayasan.com' and role='owner' and name='Owner Demo';"` |
| Quick-login hints (tenant login page and central login page) | one flag, `HALOKES_DEMO_LOGIN_HINTS=true` (repository variable or secret), then deploy. The tenant login page `/y/ABS/login` lists the five role accounts; https://halokes.com/login offers `owner@yayasan.com` **only if that account exists**. Both buttons fill the email only. To also fill a password set the secret `HALOKES_DEMO_LOGIN_PASSWORD`; that publishes it to every visitor, so it is left unset. Turn the hints off by removing the flag and redeploying |
| Check everything works | `scripts/demo-smoke.sh`. Full run, as used for the final verification: `set -a; . ~/.config/codelab/halokes.env; set +a; DEMO_OWNER_PASSWORD="$HALOKES_DEMO_OWNER_PASSWORD" EXPECT_HINTS=1 OWNER_EMAIL="$HALOKES_ADMIN_EMAIL" OWNER_PASSWORD="$HALOKES_ADMIN_PASSWORD" scripts/demo-smoke.sh`. Without `EXPECT_HINTS=1` it fails when the hints are on. It pauses about a minute when the login throttle is hit |

## Accounts

All use the shared demo password. Sign in at https://abs.halokes.com (it opens the portal `/y/ABS`).

| Role | Email | Scope |
|---|---|---|
| Super admin | `super.abs@demo.halokes.com` | the whole ABS yayasan |
| Admin TK | `admin.tk@demo.halokes.com` | TK Aboe Bakar Soemijati |
| Kepala sekolah TK | `kepsek.tk@demo.halokes.com` | TK |
| Guru TK A1 | `guru.tk.a@demo.halokes.com` | class TK A1 |
| Guru TK B1 | `guru.tk.b@demo.halokes.com` | class TK B1 |
| Admin PAUD | `admin.paud@demo.halokes.com` | PAUD Aboe Bakar Soemijati |
| Kepala sekolah PAUD | `kepsek.paud@demo.halokes.com` | PAUD |
| Guru PAUD | `guru.paud@demo.halokes.com` | class KB Mawar |
| Wali murid | `wali.01@demo.halokes.com` to `wali.31@...` | `wali.01`: Aditya Ramadhan (TK A1); `wali.22`: Alya Nugraha (KB Mawar); `wali.03`, `wali.06`, `wali.10` each have two children (TK A1 + TK B1) |
| Owner (platform), on demand | `owner@yayasan.com` | created only when **Seed demo** runs with `include_owner = true`; its password is the secret `HALOKES_DEMO_OWNER_PASSWORD` (12+ characters, **not** the shared one); sign in at https://halokes.com/login |
| Real owner | your own owner account, not part of the demo | https://halokes.com/login |

Phone numbers are fake (`0800...`); login works with the email.

## What the data covers

| Feature | Demo data |
|---|---|
| Platform landing, registration form | `saas_*` copy filled in (only keys that were empty) |
| Owner area | the ABS yayasan plus three registrations: `menunggu`, `disetujui`, `ditolak` (fictional foundations) |
| Yayasan landing and portal | landing copy, logo, hero and six gallery images (generated placeholders) |
| Schools | TK (rapor window open, kuota 25/25) and PAUD (window closed, kuota 15); logo and photo; all modules on for all roles |
| Classes and staff | TK A1, TK B1, KB Mawar; admin, kepsek and guru per school; a guru per class |
| Children (41) | 32 in classes, 2 active without a class, 6 `menunggu` with payment proof (two for next year's intake), 1 alumnus; most with full Dapodik data, some with photos |
| Parents | 31 accounts; three with two children, to try switching children |
| Attendance | 40 weekdays for every child in a class, mixed hadir/sakit/izin/alfa |
| Growth | three measurements per active child (the chart has a line) |
| Announcements | six per school: upcoming and past, for everyone, teachers or parents, one class-specific |
| Materi (LMS) | per class: two Published (one with a PDF), one Pending (waiting for the kepsek), one Rejected (with a note) |
| Jurnal harian | three themes per class group, an entry per child with some photos, comments from teacher and parent |
| Rapor | every child in a class has a rapor for the current semester: TK about 70% final (`permanen`) and 30% `draft`; PAUD all final; narrative text for every template item, two activity photos |
| Rapor archive | eight archived PDFs for the previous semester |
| Rapor template | the active template is reused; the standard one is created only if none exists |

## Tour by role

1. **Public.** https://halokes.com (platform landing, fitur, FAQ, daftar yayasan). https://abs.halokes.com (yayasan landing with the two schools, then the login page). The PPDB form is at `/y/<token>/form-pendaftaran` (the token is in the portal URL); the kuota shown is the remaining seats.
2. **Owner** (https://halokes.com/login, your account, or the demo owner `owner@yayasan.com` when enabled): yayasan list with ABS, registrations to approve or reject.
3. **Super admin:** schools (open each one's module toggles), users.
4. **Admin TK:** dashboard counters, data siswa filters (class, no class, `menunggu`, alumni, search), accepting a pending registration, attendance entry and recap, growth chart, rapor template, fill and print a rapor, archive, class promotion, pengaturan, announcements, journal, materi approval.
5. **Kepala sekolah TK:** approve or reject the Pending materi (the Rejected ones show the note).
6. **Guru TK A1:** only their class; upload a materi (becomes Pending), fill a journal entry with a photo.
7. **Wali murid** (`wali.01`): dashboard, rapor (final only), growth report, journal with photos, materi. `wali.03` to switch between two children.

## Things to know

- The attendance form always opens blank (the app does not preload saved values); the recap shows the history.
- Class promotion (Kenaikan Kelas) changes real rows; run **Seed demo** to restore.
- Re-seeding keeps what a person uploaded: logos and photos replaced through the UI are not overwritten; text that was edited stays.
- Not implemented in the app, so not in the demo: media kegiatan, notifications, audit log screens, password-reset mail, PDF generation (printing uses the browser).
- The login is throttled to five attempts per minute per address; the smoke script waits when it is throttled.
- Cloudflare rewrites email addresses in HTML as "[email protected]" (visible in lists such as the super admin's user list, harmless). Tests therefore look for page elements, not for email text.
- The yayasan landing headline shows the template's default text; the seeded hero keys are not used by the `ocean` template. Edit it in the super admin's landing settings if you want other wording.
- School hosts: nginx sends only a page view of `/login` to the portal. Logging in must POST to `/login` on the same host, so test logins through the real host, not against the app directly (see `troubleshooting.md`).
- Dates age: announcements, attendance and journal dates are relative to the day of the last seed. Run **Seed demo** again before a presentation.

## Security notes

- The demo platform owner reaches every tenant (create or switch into any yayasan, approve registrations, edit the landing) and the app has no read-only owner role. Keep it off except during a demo, use its own strong password, and run `purge` afterwards (it deletes only an account named "Owner Demo" with exactly that email).
- One simple shared password protects every demo account, including a super admin of the ABS yayasan. Anyone who has the password can change that yayasan's data. Nothing above super admin exists in the demo and your owner password is separate.
- Run `purge` when the demo is not needed. ABS is also a real customer name: demo rows are tagged and never mixed with untagged rows, but give a real school a different name instead of editing the demo ones.
- The login pages list accounts only while the hints flag is set; at the moment it is set, and the buttons fill the email only. The passwords are handed out by whoever runs the demo.
