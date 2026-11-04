#!/usr/bin/env bash
# Log in as each demo role and request the pages the demo is meant to fill; fails on any HTTP error or empty page.
# Usage: HALOKES_DEMO_PASSWORD=... scripts/demo-smoke.sh [base-url] [kode]
#   base-url  default https://abs.halokes.com     kode  default ABS
# The password is read from ~/.config/codelab/halokes.env when the variable is not set. Nothing is printed
# except page names and results. Optional: OWNER_EMAIL and OWNER_PASSWORD also check the owner area; set
# EXPECT_HINTS=1 when DEMO_LOGIN_HINTS is on; SMOKE_DUMP=<dir> keeps the page bodies. DEMO_OWNER_PASSWORD adds the
# demo platform owner (owner@yayasan.com) section; without it the central login page must not offer one.
set -uo pipefail

BASE=${1:-https://abs.halokes.com}
KODE=${2:-ABS}
ENV_FILE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}/halokes.env"
if [ -z "${HALOKES_DEMO_PASSWORD:-}" ] && [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    HALOKES_DEMO_PASSWORD=$(set -a; . "$ENV_FILE"; printf '%s' "${HALOKES_DEMO_PASSWORD:-}")
fi
[ -n "${HALOKES_DEMO_PASSWORD:-}" ] || { echo "HALOKES_DEMO_PASSWORD is not set" >&2; exit 2; }

fails=0; checks=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
bad()  { checks=$((checks + 1)); fails=$((fails + 1)); printf '  FAIL  %s\n' "$1"; }

JAR=$(mktemp); trap 'rm -f "$JAR" "$JAR.body"' EXIT

# fetch <url>  -> body in $JAR.body, status in $STATUS, final url in $FINAL
fetch() {
    STATUS=$(curl -sL -b "$JAR" -c "$JAR" --max-time 60 -o "$JAR.body" -w '%{http_code}' "$1") || STATUS=000
    FINAL=$(curl -sL -b "$JAR" -c "$JAR" --max-time 60 -o /dev/null -w '%{url_effective}' "$1") || FINAL=
}

# page <label> <path> <egrep-pattern>   (path is relative to the tenant prefix /y/<token>)
page() {
    fetch "$BASE/y/$TOKEN$2"
    dump "$1"
    if [ "$STATUS" != 200 ]; then bad "$1 -> HTTP $STATUS"; return; fi
    if grep -qiE "$3" "$JAR.body"; then ok "$1"; else bad "$1 (200 but pattern '$3' not found)"; fi
}

# dashboard <label> <pattern>: the dashboard lives at /d/<token>, outside the /y/<token> prefix
dashboard() {
    fetch "$BASE/d/$TOKEN"
    dump "$1"
    if [ "$STATUS" != 200 ]; then bad "$1 -> HTTP $STATUS"; return; fi
    if grep -qiE "$2" "$JAR.body"; then ok "$1"; else bad "$1 (200 but pattern '$2' not found)"; fi
}

# SMOKE_DUMP=<dir> keeps every page body for inspection
dump() {
    [ -n "${SMOKE_DUMP:-}" ] || return 0
    mkdir -p "$SMOKE_DUMP"
    cp "$JAR.body" "$SMOKE_DUMP/$(tr -c 'A-Za-z0-9\n' '_' <<<"$ROLE-$1").html"
}

public() { # public <label> <url> <pattern>
    : >"$JAR"
    fetch "$2"
    if [ "$STATUS" = 200 ] && grep -qiE "$3" "$JAR.body"; then ok "$1"; else bad "$1 -> HTTP $STATUS"; fi
}

login() { # login <email> <password>  -> sets TOKEN
    : >"$JAR"
    fetch "$BASE/y/$KODE/login"
    TOKEN=$(sed -E 's#.*/y/([^/]+)/login.*#\1#' <<<"$FINAL")
    local csrf kode
    csrf=$(grep -oE '<meta name="csrf-token" content="[^"]+"' "$JAR.body" | cut -d'"' -f4)
    kode=$(grep -oE 'name="kode_yayasan" value="[^"]+"' "$JAR.body" | head -1 | cut -d'"' -f4)
    local out
    out=$(curl -s -b "$JAR" -c "$JAR" --max-time 60 -o /dev/null -w '%{http_code} %{redirect_url}' \
        --data-urlencode "_token=$csrf" --data-urlencode "email=$1" --data-urlencode "password=$2" \
        --data-urlencode "kode_yayasan=$kode" "$BASE/login") || out=000
    case $out in
        302*login*) return 1 ;;
        302*) return 0 ;;
        429*) # login is throttled to 5 per minute per address: wait and try once more
            if [ "${RETRIED:-0}" = 0 ]; then RETRIED=1; sleep 62; login "$@"; local rc=$?; RETRIED=0; return $rc; fi
            return 1 ;;
        *) return 1 ;;
    esac
}

echo "== public pages ($BASE)"
public "yayasan portal /y/$KODE" "$BASE/y/$KODE" 'Aboe Bakar|TK|PAUD'
public "login portal" "$BASE/y/$KODE/login" 'csrf-token'
# The login page must not list accounts unless quick-login hints are switched on (DEMO_LOGIN_HINTS).
: >"$JAR"; fetch "$BASE/y/$KODE/login"
PTOKEN=$(sed -E 's#.*/y/([^/]+)/login.*#\1#' <<<"$FINAL")
# Cloudflare rewrites email addresses in HTML, so look for the quick-login buttons, not for the text.
if grep -q "onclick=\"fillCredentials('" "$JAR.body"; then
    if [ "${EXPECT_HINTS:-0}" = 1 ]; then ok "login page shows demo accounts (hints on, as expected)"; else bad "login page exposes demo accounts while hints should be off"; fi
else
    if [ "${EXPECT_HINTS:-0}" = 1 ]; then bad "hints expected but no demo accounts on the login page"; else ok "login page lists no accounts"; fi
fi
public "PPDB form" "$BASE/y/$PTOKEN/form-pendaftaran" 'TK|PAUD'
public "platform landing" "${HALOKES_PLATFORM_URL:-https://halokes.com}/" 'Halokes'

as() { # as <role-label> <email>
    ROLE=$(tr -c 'A-Za-z0-9\n' '_' <<<"$1")
    printf '== %s (%s)\n' "$1" "$2"
    if login "$2" "$HALOKES_DEMO_PASSWORD"; then ok "login"; else bad "login"; return 1; fi
}

NAMES='Aditya|Bima|Cakra|Dafa|Alya|Bella|Citra|Dina|Eka'
if as "super admin" "super.abs@demo.halokes.com"; then
    page "schools" "/superadmin/schools" 'Aboe Bakar Soemijati'
    page "users" "/superadmin/users" 'Rina Marlina'
fi
if as "admin TK" "admin.tk@demo.halokes.com"; then
    dashboard "dashboard" 'TK Aboe Bakar'
    page "data siswa" "/data-siswa" "$NAMES"
    page "kelas" "/kelas" 'TK A1'
    page "absensi harian" "/absensi-harian" 'TK|Absensi'
    page "rekap absensi" "/rekap-absensi" "$NAMES"
    page "perkembangan fisik" "/perkembangan-fisik" "$NAMES"
    page "isi rapor" "/isi-rapor" "$NAMES"
    page "cetak rapor" "/cetak-rapor" "$NAMES"
    page "arsip rapor" "/arsip-rapor" "$NAMES"
    page "kenaikan kelas" "/kenaikan-kelas" 'TK A1'
    page "pengaturan" "/pengaturan" 'Pengaturan|Semester'
    page "template rapor" "/admin/template" 'Kurikulum Merdeka'
    page "pengumuman" "/pengumuman" 'Maulid'
    page "jurnal harian" "/jurnal-harian" 'Tema'
    page "persetujuan materi" "/materi/persetujuan" 'Pengenalan Warna'
fi
if as "kepala sekolah TK" "kepsek.tk@demo.halokes.com"; then
    dashboard "dashboard" 'TK Aboe Bakar'
    page "persetujuan materi" "/materi/persetujuan" 'Pengenalan Warna|Prakarya'
    page "data siswa" "/data-siswa" "$NAMES"
fi
if as "guru TK A" "guru.tk.a@demo.halokes.com"; then
    dashboard "dashboard" 'TK Aboe Bakar'
    page "absensi harian" "/absensi-harian" "$NAMES"
    page "manajemen materi" "/materi/guru" 'Mengenal Huruf'
    page "jurnal harian" "/jurnal-harian" 'Tema'
fi
if as "wali murid" "wali.01@demo.halokes.com"; then
    dashboard "dashboard" "$NAMES"
    page "rapor anak" "/rapor-anak" 'Nilai Agama|Capaian'
    page "laporan fisik" "/perkembangan-anak" 'Tinggi \(cm\)'
    page "jurnal anak" "/jurnal-anak" 'Tema|kegiatan'
    page "materi" "/materi" 'Mengenal Huruf|Berhitung'
fi
if [ -n "${OWNER_EMAIL:-}" ] && [ -n "${OWNER_PASSWORD:-}" ]; then
    printf '== owner (%s)\n' "$OWNER_EMAIL"
    : >"$JAR"
    fetch "${HALOKES_PLATFORM_URL:-https://halokes.com}/login"
    csrf=$(grep -oE '<meta name="csrf-token" content="[^"]+"' "$JAR.body" | cut -d'"' -f4)
    curl -s -b "$JAR" -c "$JAR" -o /dev/null --data-urlencode "_token=$csrf" --data-urlencode "email=$OWNER_EMAIL" \
        --data-urlencode "password=$OWNER_PASSWORD" "${HALOKES_PLATFORM_URL:-https://halokes.com}/login"
    for p in /owner/yayasans /owner/yayasan-registrations; do
        fetch "${HALOKES_PLATFORM_URL:-https://halokes.com}$p"
        if [ "$STATUS" = 200 ] && grep -qE 'Aboe Bakar|Tunas|Cahaya' "$JAR.body"; then ok "owner $p"; else bad "owner $p -> HTTP $STATUS"; fi
    done
fi

# Central login page: the demo owner is offered only with hints on and the account present, never with a password.
PLATFORM=${HALOKES_PLATFORM_URL:-https://halokes.com}
printf '== central login page (%s)\n' "$PLATFORM"
: >"$JAR"; fetch "$PLATFORM/login"
offered=$(grep -oE 'window.DEMO_OWNER = [^;]*;' "$JAR.body" | head -1)
if [ -n "${DEMO_OWNER_PASSWORD:-}" ] && [ "${EXPECT_HINTS:-0}" = 1 ]; then
    if grep -q 'owner@yayasan.com' <<<"$offered"; then ok "demo owner offered (hints on)"; else bad "demo owner not offered although hints are on: $offered"; fi
else
    if [ -z "$offered" ] || grep -q 'null' <<<"$offered"; then ok "no demo owner offered"; else bad "demo owner offered unexpectedly: $offered"; fi
fi
# A short or common password (for example the word "password") also occurs in normal page markup, so a text
# search for it proves nothing; only search for passwords of at least 10 characters.
leak=0; searched=0
for pw in "$HALOKES_DEMO_PASSWORD" "${DEMO_OWNER_PASSWORD:-}"; do
    [ "${#pw}" -ge 10 ] || continue
    searched=1
    grep -qF -- "$pw" "$JAR.body" && leak=1
done
if [ "$leak" = 1 ]; then bad "a demo password appears in the central login page"
elif [ "$searched" = 1 ]; then ok "no demo password in the central login page"
else ok "central login page password search skipped (passwords shorter than 10 characters)"; fi
if [ -n "${DEMO_OWNER_PASSWORD:-}" ]; then
    printf '== demo owner (owner@yayasan.com)\n'
    : >"$JAR"
    fetch "$PLATFORM/login"
    csrf=$(grep -oE '<meta name="csrf-token" content="[^"]+"' "$JAR.body" | cut -d'"' -f4)
    code=$(curl -s -b "$JAR" -c "$JAR" -o /dev/null -w '%{http_code} %{redirect_url}' --data-urlencode "_token=$csrf" \
        --data-urlencode "email=owner@yayasan.com" --data-urlencode "password=$DEMO_OWNER_PASSWORD" "$PLATFORM/login")
    case $code in 302*owner*) ok "login" ;; *) bad "login ($code)" ;; esac
    for p in /owner/yayasans /owner/yayasan-registrations; do
        fetch "$PLATFORM$p"
        if [ "$STATUS" = 200 ] && grep -qiE 'Aboe Bakar|Tunas|Cahaya' "$JAR.body"; then ok "owner $p"; else bad "owner $p -> HTTP $STATUS"; fi
    done
fi

echo
echo "$((checks - fails))/$checks checks passed"
[ "$fails" -eq 0 ]
