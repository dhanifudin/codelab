# halokes demo (yayasan Aboe Bakar Soemijati)

A complete dataset for the yayasan with kode `ABS`, built to exercise every implemented halokes feature on:

- **https://halokes.com**: platform landing, public registration form, owner area.
- **https://abs.halokes.com**: the ABS tenant (landing, login portal, every role, PPDB form).

The data comes from `DemoSeeder` in the app repo and is created, refreshed or removed by the workflow **Seed demo (halokes)**. Everything it creates is tagged (emails end in `@demo.halokes.com`, NIKs start with `9999`, files live under `demo/abs/`), so it can be removed without touching real data.

## Setup (once)

1. The app has the `DemoSeeder` and the related fixes deployed (halokes PRs "Seed the materi modules", "Stop Jurnal Harian from republishing...", "Add DemoSeeder", "Show login-page demo accounts only when enabled").
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
| Demo platform owner | **Seed demo** with `include_owner = true` (needs the secret `HALOKES_DEMO_OWNER_PASSWORD`); `purge` removes it again |
| Show the demo owner on the central login page | set the repository variable `HALOKES_DEMO_LOGIN_HINTS=true` and deploy: https://halokes.com/login then offers a quick-fill button for `owner@yayasan.com` **if that account exists**. It fills the email only; the password is never on the page, give it to whoever needs it |
| Show demo accounts on the login page | optional and public: set the repository variable `HALOKES_DEMO_LOGIN_HINTS=true` and the secret `HALOKES_DEMO_LOGIN_PASSWORD`, then deploy. The password is then visible to every visitor of `/y/ABS/login`. Off by default |
| Check everything works | `scripts/demo-smoke.sh` (add `EXPECT_HINTS=1` when hints are on; `OWNER_EMAIL`/`OWNER_PASSWORD` to include your real owner area; `DEMO_OWNER_PASSWORD` to include the demo owner) |

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

## Security notes

- The demo platform owner reaches every tenant (create or switch into any yayasan, approve registrations, edit the landing) and the app has no read-only owner role. Keep it off except during a demo, use its own strong password, and run `purge` afterwards (it deletes only an account named "Owner Demo" with exactly that email).
- One simple shared password protects every demo account, including a super admin of the ABS yayasan. Anyone who has the password can change that yayasan's data. Nothing above super admin exists in the demo and your owner password is separate.
- Run `purge` when the demo is not needed. ABS is also a real customer name: demo rows are tagged and never mixed with untagged rows, but give a real school a different name instead of editing the demo ones.
- The login page never lists accounts unless the hints are switched on.
