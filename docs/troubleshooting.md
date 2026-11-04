# Troubleshooting

Problems met while building this setup, with the cause and the fix. For the normal procedure see [runbook.md](runbook.md).

## SSH and provisioning

| Symptom | Cause | Fix |
|---|---|---|
| `Host key verification failed` | the VPS host key is not in `known_hosts` | Compare `ssh codelab 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'` with what you expect, then accept it once from a normal terminal (`ssh codelab true`). Do not blindly accept a key you did not verify. |
| `Could not resolve hostname codelab` | no `Host codelab` entry in `~/.ssh/config` | Add the alias ([runbook](runbook.md#2-prerequisites)). |
| `kex_exchange_identification: Connection reset by peer` | sshd/fail2ban rate limit after many rapid connections | Wait a few minutes. Never poll the VPS in a tight loop; use one connection that waits (`while pgrep ...; do sleep 5; done` on the server). |
| `sudo: a password is required` during provisioning | the ssh user lacks passwordless sudo | Provisioning needs `sudo -n`; grant `NOPASSWD` to that user. |
| `apt-get update` errors about a PPA ("no longer signed", `NO_PUBKEY`) | unrelated broken repositories on the VPS | Provisioning continues with the existing package index (`warn`), installing from already-indexed repos. Fix the repository separately before the next system upgrade. |
| Provisioning output ends in `command not found` lines from `*.env` | a stray line in `~/.config/codelab/<site>.env` (for example tool output written by mistake) | Open the file, keep only `KEY=value` lines, mode 600. |
| `.env`-style file has a first line like `0 matches for ...` | a `grep -v` on an empty file was run through a wrapper that prints a summary | Delete that line; write such files with `printf`, not through a filtered `grep`. |
| Second provisioning run still shows `changed:` | a step is not idempotent | Read the line: `changed: <file>` means the rendered content differs on every run (look for timestamps or randomness in the template). |
| `pending: DNS does not point at this server yet for: host(1.2.3.4)` | foreign DNS not updated, or a proxied record | Wait for the record. For a proxied (Cloudflare orange cloud) record set `TLS_DNS_CHECK=skip` and use SSL mode Full (strict). |
| `pending: vhost for <domain> not installed yet` | first run with DNS already pointing here | Run provisioning once more; the ACME location must be live before the certificate is requested. |
| `certbot failed ... continuing over HTTP` | validation failed (DNS, port 80, firewall) | `sudo tail -50 /var/log/letsencrypt/letsencrypt.log`; fix, re-run provisioning. Manual fallback: `sudo certbot certonly --webroot -w /var/www/letsencrypt --cert-name <domain> -d <domain>`. |
| `nginx config invalid; previous vhost restored` | a template change broke `nginx -t` | The previous config is back and the site is up. Fix the template; test with `nix run nixpkgs#nginx -- -t` against a rendered copy, then re-run. |
| `php-fpm config invalid; pool removed` | invalid pool file | The running fpm is untouched. Fix `php-fpm-pool.conf`. |
| Other sites hiccup after provisioning | installing a PHP extension makes dpkg reload a shared php-fpm | This is a graceful reload; pools are added with `reload`, never `restart`. |

## Deploys

| Symptom | Cause | Fix |
|---|---|---|
| Checkout step fails: repository not found | `APP_READ_TOKEN` cannot see the private app repo | Add the repo to the token's repository list ([tokens.md](tokens.md)). The secret value does not change. |
| `required variable <SITE>_... is empty` | a secret is missing or empty | `gh secret list --repo dhanifudin/codelab`; re-run `setup-github.sh <site>` (existing generated values are reused). |
| `client_payload.sha is not a 40-hex commit id` / `ref contains unexpected characters` | the validation step rejected the input | Dispatch with a full commit sha, or a branch/tag name made of letters, digits, `. _ / -`. |
| Smoke test fails, run rolls back | the app returned something other than 200 for `SMOKE_PATH` | Read the run log, then the app's own logs: `sudo tail /var/log/php<ver>-fpm-<pool>.log`, `/var/www/<domain>/shared/storage/logs`, `/var/log/nginx/<site>.error.log`. The previous release is already active again. |
| `migrate` fails on an empty database | the app has no `create_*` migrations | The app needs a schema baseline (`database/schema/mysql-schema.sql`), as halokes got in its PR #1. |
| Uploaded files vanish after a deploy | the upload folder is not in `shared-paths.txt` | Add it, deploy again (the files already lost are gone). |
| Sample files from the app repo show up in production | folder is shared but seeded from the release | Mark it `empty` in `shared-paths.txt` and exclude the samples in `rsync-exclude.txt`. |
| `release <path> missing` or `.env missing` in `activate.sh` | the rsync/upload step failed earlier | Re-run the workflow; check disk space on the VPS. |
| Go site: `restart of <service> failed; switched back` | the new binary does not start | `journalctl -u <service> -n 50`; the previous binary is active again. |

## DNS and Cloudflare

| Symptom | Cause | Fix |
|---|---|---|
| Browser shows 526 / wrong certificate for a new host | DNS was created before the origin served the host, so nginx used another site's certificate | Order matters: provision and verify with `curl --resolve host:443:<ip> https://host/` first, create DNS last. |
| `cf-dns.sh`: `zone ... not found for this token` | zone not added, or token scoped to another zone | Add the zone; recreate the token with Zone Read on it. |
| `cf-dns.sh`: `CF_API_TOKEN has an unexpected format` | placeholder text or wrong value in `cloudflare.env` | Put the real token (`CF_API_TOKEN=...`, mode 600). |
| `cf-dns.sh`: `cannot read config from /dev/fd/63` | old script version | Pull the current repo (token now goes via stdin). |
| certbot DNS-01: `Unable to determine zone_id` | certbot token lacks Zone Read, or covers a different zone | Recreate with Zone Read and DNS Edit on the zone. |
| `CF_CERTBOT_TOKEN equals the dns-admin token` | least-privilege check in the wizard | Create a separate certbot token, or set `ALLOW_SAME_CF_TOKEN=1` knowingly. |
| New subdomain returns 404 from the wrong site | the host is not in `SERVER_NAMES`, or not provisioned | Add it, re-run provisioning. Wildcard certificates do not route hosts. |
| Nameservers changed but the zone stays "pending" | the change has not propagated | `dig NS <domain> @a.gtld-servers.net` must show the Cloudflare nameservers; wait. |

## Login and application checks

| Symptom | Cause | Fix |
|---|---|---|
| `419` when testing login with curl | missing or stale CSRF token or session after an earlier login | Fetch the token from the login page's `<meta name="csrf-token">` with a fresh cookie jar. |
| "Wrong yayasan" on `/login` for a school user (halokes) | school users sign in at `/y/<token>/login` | Use the school portal; only owners use `/login`. |
| Password forgotten, no reset mail | `MAIL_MAILER=log` | Reset from the server with artisan, or configure SMTP. |
| Laravel 9 shows deprecation notices on PHP 8.4 | framework age | They stay out of responses with `APP_DEBUG=false`; if something fatal appears, install another PHP version from the PPA and set `PHP_VERSION`. |

## abs.halokes.com / school hosts

| Symptom | Cause | Fix |
|---|---|---|
| Login on a school host just returns to the login page, with the right password | an nginx rule redirected the login form's POST (`/login`) to the portal, turning it into a GET | fixed in `sites/halokes/nginx.conf` (`$tenant_login_kode` redirects only GET/HEAD); re-run provisioning. Testing the app directly (bypassing nginx) cannot catch this, so test logins through the real host |
| Emails show as `[email protected]` in page text | Cloudflare email obfuscation rewrites addresses in HTML | cosmetic; tests must not match on email text |

## Tooling quirks

- `certbot renew --dry-run` takes several minutes (one challenge per name, each waiting for DNS). Start it detached on the server and read `/var/log/letsencrypt/letsencrypt.log` for `all simulated renewals succeeded`; an interrupted run ends with "Calling signal 15" and proves nothing.
- A post-hook in `/etc/letsencrypt/renewal-hooks/post/` runs for every renewal on this VPS and can print its own errors unrelated to a given site's certificate.
- Scripts run through `sudo` over ssh without a tty; interactive prompts do not work there, which is why secrets arrive on stdin.
- `shellcheck` info/warning notes about `source` of a computed path (`SC1090`) and `ls` loops in `activate.sh` are known and harmless.
- When a command is run through a CLI wrapper that rewrites `grep`/`ls` output, use `rg`, `awk` or explicit options in scripts you intend to keep; scripts here avoid depending on such output formats.
