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

Gotcha (fail2ban): the Debian default  makes a jail ignore . Every jail that reads a log file
needs  ( must list the files, not "No file is currently monitored").
