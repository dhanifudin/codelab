# DNS and HTTPS cutover for spi.polinema.ac.id

DNS for `polinema.ac.id` is controlled by Polinema IT, so this is a request plus a few commands.

## 1. Test before DNS

1. Add to `/etc/hosts` on your machine: `194.127.193.198 spi.polinema.ac.id`
2. Browse to `http://spi.polinema.ac.id` and log in with the Super Admin from the bootstrap workflow.
3. Remove the line when done, so you test real DNS later.

reCAPTCHA keys must list `spi.polinema.ac.id` as an allowed domain. Until keys exist, leave `SPI_NOCAPTCHA_*` unset (the login form may still render the widget; that is an app issue tracked for v2).

## 2. Ask Polinema IT

Create an `A` record: `spi.polinema.ac.id` to `194.127.193.198` (check the server's current public IP first). Port 80 and 443 must be reachable from the internet, because Let's Encrypt validates over HTTP.

## 3. Issue the certificate

After `dig +short spi.polinema.ac.id` returns the server IP:

```bash
ssh codelab
sudo certbot --nginx -d spi.polinema.ac.id
```

Certbot edits `/etc/nginx/sites-available/spi.polinema.ac.id.conf` in place and installs renewal. Re-running `provision/provision.sh` afterwards would overwrite those edits with the repo's HTTP-only vhost. Before the next provisioning run, copy the certbot-managed server blocks back into `sites/spi/nginx.conf` (keeping the `@VAR@` placeholders) and commit.

## 4. Switch the app to HTTPS

```bash
gh variable set SPI_APP_URL --body https://spi.polinema.ac.id --repo dhanifudin/codelab
```

Then run **Deploy spi**. This sets `APP_URL` and `SESSION_SECURE_COOKIE=true`.

## Later: halokes.com

Same process with a `sites/halokes/` directory once the server, repo and domain exist.
