# Server hardening (codelab VPS)

What is configured by hand on the VPS, outside `provision/`, and how to check it. Applied 2026-11-13.

| Area | Setting | Verify |
|---|---|---|
| SSH | Keys only. `/etc/ssh/sshd_config.d/00-hardening.conf` (loaded before `50-cloud-init.conf`, first match wins): `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `AllowUsers el deploy`, `MaxAuthTries 3`, `LoginGraceTime 20` | `sudo sshd -T \| grep -E 'passwordauthentication\|allowusers'`; `ssh -o PubkeyAuthentication=no host` is refused |
| Firewall | `ufw` default deny; only 22, 80, 443 are open for services that run. Remove a rule when the service goes away | `sudo ufw status`; `ss -ltn` shows only 22, 80, 443 outside loopback (plus any container on the host network, which ufw still blocks) |
| nginx | `ssl_protocols TLSv1.2 TLSv1.3`; `server_tokens off`; `conf.d/00-default.conf` drops requests for unknown host names (444) and rejects TLS handshakes without a matching name | `curl -k https://<ip>/` gets no answer |
| fail2ban | Jails `sshd`, `wordpress-login` (5 failed `POST /wp-login.php`, status 200 or 429, in 10 minutes gives a 1 hour ban), `nginx-probe` (scanner requests that end in an error: `.env`, `.git`, `phpinfo.php`, `xmlrpc.php`, ...), `nginx-botsearch`, `recidive`. Filter `/etc/fail2ban/filter.d/nginx-probe.conf`, jails `/etc/fail2ban/jail.d/nginx-hardening.conf` | `fail2ban-client status`; `fail2ban-regex <access.log> nginx-probe` before changing the filter |
| Secrets | `.env` and `config/database.php` of apps that run as `www-data`: owner = the deploy user, group `www-data`, mode 640; other `.env` files 600. Never "others" readable | `find /var/www -maxdepth 4 -name .env -perm /o+r` is empty |
| sudo | `deploy` only has the commands that the site provisioning writes (`reload php<ver>-fpm`) plus the legacy `restart nginx` and `nginx -t` | `sudo -l -U deploy` |
| Updates | `unattended-upgrades` on; a reboot is needed after kernel or libc updates (`/var/run/reboot-required`) | `uname -r` equals the newest installed `linux-image` |
| Removed | `code-server` is stopped and disabled; its vhosts return 503. Unused ufw rules for mail and other ports were removed | `systemctl is-active code-server@el` |

Rules of thumb when adding a site: give it its own php-fpm pool and unix user (as `provision/30-site.sh` does), keep secrets
in `shared/` with mode 600 owned by the deploy user, never put database dumps or archives in a web root, and add the vhost
only after `nginx -t` passes.

Gotcha (fail2ban): the Debian default `backend = systemd` makes a jail ignore `logpath`. Every jail that reads a log file
needs `backend = auto` (`fail2ban-client get <jail> logpath` must list the files, not "No file is currently monitored").

## Second round (2026-11-13)

| Area | Setting | Verify |
|---|---|---|
| Logs | journald capped (`/etc/systemd/journald.conf.d/50-limits.conf`: 500M, keep 1G free, 1 month); `/etc/logrotate.d/rsyslog` rotates weekly or at 100M and has `su root syslog` (without it logrotate skipped syslog because `/var/log` is group-writable by `syslog`) | `journalctl --disk-usage`; `ls -la /var/log/syslog*` |
| Kernel | `/etc/sysctl.d/99-hardening.conf`: no ICMP redirects sent, martian logging, `fs.suid_dumpable=0`, unprivileged BPF off (`ip_forward` stays 1 for Docker); core dumps off (`limits.d/99-no-core.conf`) | `sysctl -n fs.suid_dumpable` |
| SSH | keepalive 300s x2, `LogLevel VERBOSE` (in `00-hardening.conf`) | `sshd -T` |
| MariaDB | `local_infile=0` (`mariadb.conf.d/99-hardening.cnf`) | `SHOW VARIABLES LIKE 'local_infile'` |
| Updates | `52unattended-reboot`: automatic reboot at 04:30 (server time) only when an update needs it | `/var/run/reboot-required` does not linger |
| PHP pools | One pool and one system user per non-codelab Laravel site (`app-<site>`, socket `/run/php/php<ver>-fpm-app-<site>.sock`, `open_basedir` = site dir + its state dir, exec-type functions disabled). Code `el:app-<site>` 750/640, `public/` 755/644, `.env` 640, `storage/` and `bootstrap/cache/` owned by the pool user with setgid dirs; `el` is in each group. Old modes and vhost are kept in `/root/pool-split/<site>.*` for rollback | `ps -eo user,args` shows `pool app-<site>`; another pool user cannot read the `.env` |
| nginx | HSTS on the https vhosts that serve working apps | `curl -I` |
| Monitoring | monit checks (restart on failure) for nginx, php-fpm 8.4 and 8.5, mariadb, redis, fail2ban, sshd, docker, plus disk; results in `/var/log/monit.log`; `monit summary` works through `/run/monit.sock` | `sudo monit summary` |
| Audit | auditd with watches on identity files, sudoers, ssh config and keys, nginx/php/fail2ban/ufw config, cron, systemd units, WordPress `mu-plugins` and `wp-config.php` | `/var/log/audit/audit.log` |
| Cleanup | removed snapd, apport, ftp, telnet; ModemManager disabled; host `postgres` user has no shell | `systemctl --failed` is empty |

Lynis hardening index after this round: 74 (no warnings).

