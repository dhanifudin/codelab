# spi.polinema.ac.id: first deploy, DNS and HTTPS

The DNS zone `polinema.ac.id` is managed by Polinema IT, so the certificate is issued over HTTP-01 (`TLS=letsencrypt-webroot` in `sites/spi/site.conf`): IT only has to point the A record at this server. Provisioning checks DNS itself and keeps the site on plain HTTP until it does.

## 1. One-time setup

1. **Read access to the private app repo.** `APP_READ_TOKEN` must be able to read `dhanifudin/spi.polinema.ac.id`: GitHub, Settings, Developer settings, Fine-grained tokens, open the token, Repository access, add the repo (see `docs/tokens.md`).
2. `scripts/setup-github.sh spi` in a normal terminal. It generates the app key, DB password and admin password into `~/.config/codelab/spi.env` and sets the `SPI_*` secrets.
3. `scripts/provision-remote.sh codelab spi` (run it twice; the second run must report no changes). Then run **Deploy spi** and **Bootstrap spi data** from the Actions tab.

User-data folders (`hasil_*`, `koreksi_*`, `surat_tugas`, `sertifikat`, `tanda_tangans`, ...) start empty on purpose: the sample files committed in the app repo are neither uploaded nor copied into production. Only the document templates (`template_*`) and the `storage` skeleton are seeded.

## 2. Test before DNS

Add `194.127.193.198 spi.polinema.ac.id` to `/etc/hosts` on your machine, open `http://spi.polinema.ac.id` and log in with the Super Admin from the bootstrap. Remove the line afterwards so you test real DNS later. The site is HTTP-only at this stage.

## 3. Ask Polinema IT

Today the record points at `103.170.197.231`, which does not answer. Message to send:

> Please change the DNS record for `spi.polinema.ac.id` to an `A` record with value `194.127.193.198` (the Cloudflare orange cloud off, "DNS only", if the zone is proxied). Ports 80 and 443 on that address are open. We use Let's Encrypt for HTTPS, which validates over port 80, so the record must stay pointed at this address.

## 4. After the record changes

1. `dig +short spi.polinema.ac.id @1.1.1.1` returns `194.127.193.198`.
2. `scripts/provision-remote.sh codelab spi`. The log shows `certificate issued for spi.polinema.ac.id` and the vhost switches to HTTPS (HTTP redirects to HTTPS, HSTS 30 days). While DNS is wrong it logs `pending:` instead and nothing breaks.
3. If `pending: vhost for ... not installed yet` appears, run provisioning once more.
4. `gh variable set SPI_APP_URL --body https://spi.polinema.ac.id --repo dhanifudin/codelab`, then run **Deploy spi** so `APP_URL` and secure cookies apply.
5. Proxied record (orange cloud) instead of DNS only: set `TLS_DNS_CHECK=skip` in `site.conf` (the resolved address is then a Cloudflare one) and use SSL mode Full (strict) on their side.

## 5. Auto-deploy

The app repo already contains `.github/workflows/notify-codelab.yml`. Create `CODELAB_DISPATCH_TOKEN` (`docs/tokens.md`, section 4) and set it with `gh secret set CODELAB_DISPATCH_TOKEN --repo dhanifudin/spi.polinema.ac.id`.

## If the certificate fails

The site keeps serving over HTTP and the next provisioning run retries. See `/var/log/letsencrypt/letsencrypt.log`. Manual fallback: `sudo certbot certonly --webroot -w /var/www/letsencrypt --cert-name spi.polinema.ac.id -d spi.polinema.ac.id`, then re-run provisioning.

## Rolling DNS back

Point the record back to the previous address. The VPS keeps the certificate; nothing needs to change here.
