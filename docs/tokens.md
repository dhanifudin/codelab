# Where every token comes from

Four tokens are involved. None of them is ever committed. Each section says where to create it, which permissions to tick, and where the value ends up. Values are shown once when created, so copy them straight into the destination.

Generated for you, not tokens: the Laravel app key, the database password and the admin password (`scripts/setup-github.sh` creates them and keeps them in `~/.config/codelab/<site>.env`).

## 1. Cloudflare "dns-admin" token (`CF_API_TOKEN`)

Used locally by `scripts/cf-dns.sh` to create DNS records and zone settings.

1. Open https://dash.cloudflare.com and click your profile icon (top right), then **My Profile**.
2. **API Tokens**, then **Create Token**, then **Create Custom Token** (at the bottom of the list).
3. Name: `codelab-dns-admin`.
4. Permissions, three rows:
   - **Zone**, **Zone**, **Read**
   - **Zone**, **DNS**, **Edit**
   - **Zone**, **Zone Settings**, **Edit**
5. Zone Resources: **Include**, **Specific zone**, `halokes.com`.
6. **Continue to summary**, then **Create Token**. Copy the token.
7. Store it: `install -m 600 /dev/null ~/.config/codelab/cloudflare.env && printf 'CF_API_TOKEN=%s\n' 'THE_TOKEN' >> ~/.config/codelab/cloudflare.env`

## 2. Cloudflare "certbot" token (`CF_CERTBOT_TOKEN`)

Installed on the VPS (`/etc/letsencrypt/cloudflare/halokes.ini`, root only) so certbot can answer the Let's Encrypt DNS challenge. It is deliberately a second token with fewer permissions than the first: it cannot change zone settings.

1. Same page as above: **My Profile**, **API Tokens**, **Create Token**, **Create Custom Token**.
2. Name: `codelab-certbot`.
3. Permissions, two rows:
   - **Zone**, **Zone**, **Read** (certbot looks up the zone id)
   - **Zone**, **DNS**, **Edit**
4. Zone Resources: **Include**, **Specific zone**, `halokes.com`.
5. Create the token and copy it.
6. Pass it to the wizard as `CF_CERTBOT_TOKEN` (see section 5), or type it at the hidden prompt.

## 3. GitHub `APP_READ_TOKEN`

Lets GitHub Actions in `dhanifudin/codelab` download the private app repo (`dhanifudin/halokes`) to build it. Not needed for a public app repo.

1. https://github.com/settings/personal-access-tokens/new (or: profile photo, **Settings**, **Developer settings**, **Personal access tokens**, **Fine-grained tokens**, **Generate new token**).
2. Token name `codelab-read-halokes`, an expiration (90 days is reasonable; put a reminder in your calendar), Resource owner `dhanifudin`.
3. Repository access: **Only select repositories**, then `halokes`.
4. Permissions, **Repository permissions**: **Contents** = **Read-only**. (**Metadata: Read-only** is added automatically.)
5. **Generate token** and copy it (starts with `github_pat_`).
6. Pass it to the wizard as `APP_READ_TOKEN`; it becomes a secret in `dhanifudin/codelab`. Manual alternative: `gh secret set APP_READ_TOKEN --repo dhanifudin/codelab`.

## 4. GitHub `CODELAB_DISPATCH_TOKEN`

Lets the app repo tell `codelab` to deploy (`repository_dispatch`) after each push to `main`. You need it only after the notify workflow PR is merged in the app repo.

1. Same page: https://github.com/settings/personal-access-tokens/new.
2. Name `codelab-dispatch`, an expiration, Resource owner `dhanifudin`.
3. Repository access: **Only select repositories**, then `codelab`.
4. Permissions, **Repository permissions**: **Contents** = **Read and write** (GitHub requires write access to send a dispatch event).
5. Generate and copy the token.
6. Store it as a secret **in the app repo**: `gh secret set CODELAB_DISPATCH_TOKEN --repo dhanifudin/halokes` (paste when asked).

## 5. Running the wizard

In a normal terminal (recommended; it prompts and hides token input):

```
scripts/setup-github.sh halokes
```

Non-interactively, with values from the environment (they end up in your shell history, so prefer the terminal):

```
CONFIRM_FINGERPRINT=SHA256:... HALOKES_ADMIN_NAME="Your Name" HALOKES_ADMIN_EMAIL=you@example.com \
CF_CERTBOT_TOKEN=... APP_READ_TOKEN=... scripts/setup-github.sh halokes
```

## If a token leaks

Revoke it where it was created (Cloudflare: API Tokens, Roll or Delete; GitHub: Settings, Developer settings, delete the token), create a new one with the same permissions, and replace the stored copy (`cloudflare.env`, `halokes.env`, or `gh secret set ...`). The pipeline needs no other change.
