#!/usr/bin/env bash
# Runs on the VPS as the deploy user: bash -s -- spi
# Seeds REFERENCE data only and creates one Super Admin.
# Admin details arrive on stdin (never argv), one per line, in this order:
#   name, email, username (also used as NIP), password
# The app's UserData/PetaSeeder/PostSeeder/BeritaAcaraSeeder are never run: they create demo
# accounts with default credentials.
set -euo pipefail

SITE=${1:?site}
# shellcheck source=/dev/null
source "/etc/codelab/$SITE.conf"
PHP="php$PHP_VERSION"

IFS= read -r SPI_ADMIN_NAME
IFS= read -r SPI_ADMIN_EMAIL
IFS= read -r SPI_ADMIN_USERNAME
IFS= read -r SPI_ADMIN_PASSWORD
export SPI_ADMIN_NAME SPI_ADMIN_EMAIL SPI_ADMIN_USERNAME SPI_ADMIN_PASSWORD
[ -n "$SPI_ADMIN_EMAIL" ] && [ "${#SPI_ADMIN_PASSWORD}" -ge 12 ] || { echo "admin email empty or password shorter than 12" >&2; exit 1; }

cd "$BASE/current"

# Order matters: levels, menus and unit_kerjas are foreign-key targets.
SEEDERS=(
    LevelSeeder
    MenuData
    LevelMenuSeeder
    ManajemenSuratMenuSeeder
    UnitKerjaData
    ManagementElementSeeder
    ManagementSubElementSeeder
    ManagementTopicSeeder
    UraianSeeder
    ManagementPengawasanSeeder
    JenisKegiatanSeeder
)

php_app() {
    "$PHP" -r '
        require "vendor/autoload.php";
        $app = require "bootstrap/app.php";
        $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
        '"$1"
}

# The app seeders are plain inserts (not idempotent): skip when already seeded.
levels=$(php_app 'echo Illuminate\Support\Facades\DB::table("levels")->count();')
if [ "$levels" != 0 ] && [ "${FORCE_RESEED:-0}" != 1 ]; then
    echo "levels already has $levels rows: skipping reference seeders"
else
    for s in "${SEEDERS[@]}"; do
        echo "seeding $s"
        "$PHP" artisan db:seed --class="$s" --force --no-interaction
    done
fi

php_app '
    $db = Illuminate\Support\Facades\DB::class;
    $email = getenv("SPI_ADMIN_EMAIL");
    $unit = $db::table("unit_kerjas")->orderBy("id")->value("id");
    if (!$unit) { fwrite(STDERR, "no unit_kerjas rows: seeding failed\n"); exit(1); }
    $row = [
        "name" => getenv("SPI_ADMIN_NAME"),
        "username" => getenv("SPI_ADMIN_USERNAME"),
        "nip" => getenv("SPI_ADMIN_USERNAME"),
        "password" => password_hash(getenv("SPI_ADMIN_PASSWORD"), PASSWORD_BCRYPT),
        "id_level" => 1,
        "id_unit_kerja" => $unit,
        "is_approved" => 1,
        "email_verified_at" => now(),
        "updated_at" => now(),
    ];
    if ($db::table("users")->where("email", $email)->exists()) {
        $db::table("users")->where("email", $email)->update($row);
        echo "super admin updated\n";
    } else {
        $db::table("users")->insert($row + ["email" => $email, "created_at" => now()]);
        echo "super admin created\n";
    }
'
