# Moving halokes.com to Cloudflare

halokes.com is registered at Rumahweb and its nameservers (`nsid1-4.rumahweb.*`) currently serve an empty zone: no A, MX or TXT records. Moving to Cloudflare therefore loses nothing. The registrar stays Rumahweb; only the nameservers change.

DNS records and zone settings live in this repo (`sites/halokes/dns.records`, `sites/halokes/cf-zone-settings`) and are applied by `scripts/cf-dns.sh`.

## Steps

1. **Add the zone.** In Cloudflare, Add a site, `halokes.com`, Free plan. Note the two nameservers it assigns (for example `xxx.ns.cloudflare.com`).
2. **Create two API tokens** (My Profile, API Tokens, Create Token, Custom token). Restrict both to the zone `halokes.com`.
   - **dns-admin** (used locally by `cf-dns.sh`): Zone: Zone Read, Zone: DNS Edit, Zone: Zone Settings Edit.
   - **certbot** (installed on the VPS for DNS-01): Zone: DNS Edit only.
3. **Store token A locally:** `install -m 600 /dev/null ~/.config/codelab/cloudflare.env && echo 'CF_API_TOKEN=...' >> ~/.config/codelab/cloudflare.env`.
4. **Apply records and settings:** `scripts/cf-dns.sh halokes --dry-run`, then without `--dry-run`. A second run must print only `unchanged:` lines. Records not listed in `dns.records` are reported as `unmanaged:` and never deleted.
5. **Switch nameservers at Rumahweb.** In the Rumahweb client area, domain halokes.com, Nameservers, replace the four `nsid*` entries with the two Cloudflare nameservers. Check that DNSSEC is off at Rumahweb first (it has no effect on an empty zone, but a stale DS record breaks resolution after the switch).
6. **Wait for propagation.** `dig NS halokes.com @a.gtld-servers.net` should list the Cloudflare nameservers (up to a few hours). The Cloudflare dashboard then shows the zone as Active.
7. **Provision the VPS** (`scripts/provision-remote.sh codelab halokes`). The certificate is issued by Let's Encrypt via DNS-01 with token B, so it only needs the zone to be active on Cloudflare, not the server to be reachable yet.

## How it fits together

- `@` and `www` are proxied (orange cloud), so the VPS IP is hidden. Zone settings: SSL mode Full (strict), Always Use HTTPS, minimum TLS 1.2.
- nginx restores client IPs from `CF-Connecting-IP` using Cloudflare's published ranges (`provision/26-cloudflare-ips.sh`, refreshed on every provisioning run).
- The deploy smoke test goes straight to the origin (`curl --resolve halokes.com:443:<vps-ip>`), so a Cloudflare cache or outage cannot hide a broken release.
- Cloudflare's free plan allows 100 MB uploads, above the app's 20 MB video limit.

## Adding a tenant domain later

Add its names to `SERVER_NAMES` in `sites/halokes/site.conf`, its records to `dns.records`, re-run `cf-dns.sh` and provisioning (the cert is re-issued with `--expand`), then insert a row in the app's `domains` table. A tenant domain must also be a zone in the same Cloudflare account, or use DNS-only records pointing at the VPS.
