# spi: loading the SIMKEU risks and the SPI staff

Done once on 2026-11-11 after the first deploy. The two Excel files (`Data SIMKEU 2026 untuk SPI`, `Daftar_Email_Polinema`) hold NIPs, emails and budgets, so they are never committed and are deleted from the VPS after use.

## Commands (in the app repo, `app/Console/Commands`)

| Command | What it does |
|---|---|
| `spi:import-staff <xlsx> --password-stdin [--reset-passwords] [--dry-run]` | Creates or updates accounts by email: username and NIP from the file, approved, email verified, unit SPI. Ketua, Sekretaris and Anggota map to their levels; the two "Admin" rows are Super Admins. The password is read from STDIN and only applied to new users (or all, with `--reset-passwords`). |
| `spi:import-simkeu <xlsx> [--dry-run]` | Loads the rows whose `idUsulan` looks like `N-2026-N` (the final 2026 plan) into `kegiatans` and `petas`, keyed on `idUsulan`. Re-running updates content columns and never resets workflow state. Rows without impact/probability, or with an unknown unit, are skipped and listed. |

The sheet also holds 672 `USUL…` rows: the earlier proposals of the same activities. They are ignored (`--id-pattern` changes that); loading both would double every budget.

## Procedure

```bash
# files: scp to a 0700 directory owned by deploy, run, delete
D=/var/www/spi.polinema.ac.id/shared/imports
A="cd /var/www/spi.polinema.ac.id/current && sudo -u deploy php8.4 artisan"
printf '%s\n' "$SPI_STAFF_PASSWORD" | ssh codelab "$A spi:import-staff $D/staff.xlsx --password-stdin --reset-passwords"
ssh codelab "$A spi:import-simkeu $D/simkeu.xlsx"          # add --dry-run first
```

`SPI_STAFF_PASSWORD` lives in `~/.config/codelab/spi.env` on the operator's machine, never in GitHub or git.

## Result (2026-11-11)

10 users, 665 kegiatans, 665 petas (all hidden: `tampil_manajemen_risiko = 0`), 97 units (ids 94-97 are new). Risk level is `Extreme` (score >= 15), `High` (>= 10), `Moderate` (>= 5) or `Low`, the vocabulary the dashboards filter on.

Not loaded: three `Institusi` fund lines with no risk assessment (`99-2026-6` Dana Kerjasama Rp 1.02 bn, `99-2026-7` Dana Reciprokal Rp 15.27 bn, `99-2026-9` Kegiatan Penunjang Rp 1.55 bn). Add them by hand if they should carry a risk.

## Open items

Operator steps and known gaps for this site are tracked in the private app repository (`docs/spi-open-items.md`), not in this public repo.

## Known limits of the app's own importer (not used here)

`PetaRisikoImport` expects raw SIMKEU column names (`nmKegiatan`, `nmUnit`, ...), keys rows on title + unit (several risks of one activity collapse into one), stores `MIDDLE`/`VERY LOW` levels the dashboards never count, and never links a risk to a `Kegiatan`. Its result message also throws on an undefined array key after a successful import.
