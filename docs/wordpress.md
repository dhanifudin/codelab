# WordPress sites on the VPS

Not managed by `provision/` (that is for app repos). Set up by hand, one pattern per site. Applied 2026-11-13 when the old
sites were rebuilt.

## Layout
- One system user and one php-fpm pool per site (PHP 8.4): `wp-<site>`, socket `/run/php/php8.4-fpm-wp-<site>.sock`,
  state in `/var/lib/wp-<site>/` (tmp, sessions), log `/var/log/php8.4-fpm-wp-<site>.log`.
  The pool sets `open_basedir` to the site directory plus its state dir and `disable_functions` for exec, system, shell_exec,
  passthru, proc_open, popen and friends.
- Code is owned by root and read-only to the pool user. Only `wp-content/uploads` belongs to the pool user.
  `wp-config.php` is `640 root:wp-<site>`. `DISALLOW_FILE_EDIT` and `DISALLOW_FILE_MODS` are on, so updates are done by the
  operator with WP-CLI, never from wp-admin.
- Database `wp_<site>`, user `wp_<site>` limited to that database. Generated passwords live only in
  `/root/wp-secrets/<site>.env` (mode 600) and in `wp-config.php`.
- nginx vhost from `docs/templates/wordpress-vhost.conf.tpl` (placeholders `@DOMAIN@`, `@SITE@`, `@ROOT@`) plus the shared
  login rate-limit zone `docs/templates/wordpress-limits.conf` in `/etc/nginx/conf.d/`. It denies dotfiles, dumps and
  archives, `xmlrpc.php` and any PHP under `uploads`.

## Operating
- WP-CLI is `/usr/local/bin/wp` (official phar, checksum verified). Run it as root with the right interpreter and path:
  `php8.4 /usr/local/bin/wp --allow-root --path=/var/www/<domain> <command>`.
- Install core from the official zip (`wordpress-<ver>.zip` plus its `.sha1`) and unzip it; do not use `wp core download` here
  (its tar extraction truncates long file names). Then `wp core verify-checksums`.
- Plugins and themes only from wordpress.org (`wp plugin install`, then `wp plugin verify-checksums --all`). No premium or
  nulled code.
- Update: `wp core update`, `wp plugin update --all`, `wp theme update --all`; because file modifications are locked, temporarily
  use `--skip-plugins` or `wp config set DISALLOW_FILE_MODS false --raw`, update, then set it back to `true`.
- Never put SQL dumps or archives under a web root. Take dumps with `mysqldump` to a private directory.
- After any incident: compare `wp-content` with a clean install (`mu-plugins` must normally be absent), list administrators
  (`wp user list --role=administrator`), check `wp cron event list` and the options table for unknown entries.
- Cleaning up spam attachments: `wp post delete --force` on an attachment also deletes its file on disk. Copy the files aside
  first (or delete the rows with SQL and keep the files), and compare the image URLs used by the remaining content with the
  files on disk before and after.

## Notes on rebuilt sites
- ulfillah.com runs Olsen Light 1.8.0 on purpose (the old site ran 1.7.1, identical to the official release). To keep the
  old look: the "Paragraphs in Arial" rule that the closed Easy Google Fonts plugin applied lives in Customize > Additional CSS,
  and `archive_title` is set to 0 (`wp theme mod set archive_title 0`). Easy Google Fonts was removed from wordpress.org
  (2026-09-09) and is not reinstalled.
- Jetpack is installed but must be reconnected by the site owner from wp-admin; until then its modules, including the image
  CDN (Photon), are off and the log shows harmless cron schedule messages.
