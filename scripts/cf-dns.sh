#!/usr/bin/env bash
# Idempotently apply sites/<site>/dns.records and sites/<site>/cf-zone-settings to Cloudflare.
# Never deletes records: ones not listed are reported as "unmanaged".
# Usage: scripts/cf-dns.sh <site> [--dry-run]
# Token: CF_API_TOKEN in ~/.config/codelab/cloudflare.env (mode 600), scopes on the zone:
#        Zone:Read, DNS:Edit, Zone Settings:Edit. Sent via a curl config on a pipe, never argv.
set -euo pipefail

SITE=${1:?usage: cf-dns.sh <site> [--dry-run]}
DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITE_DIR="$HERE/../sites/$SITE"
ENV_FILE="${CODELAB_ENV_DIR:-$HOME/.config/codelab}/cloudflare.env"
API=https://api.cloudflare.com/client/v4

command -v jq >/dev/null && command -v curl >/dev/null || { echo "need curl and jq" >&2; exit 1; }
# shellcheck source=/dev/null
source "$SITE_DIR/site.conf"
: "${CF_ZONE:?site.conf has no CF_ZONE}"
if [ -z "${CF_API_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    set -a; . "$ENV_FILE"; set +a
fi
[ -n "${CF_API_TOKEN:-}" ] || { echo "CF_API_TOKEN not set (expected in $ENV_FILE)" >&2; exit 1; }
[[ "$CF_API_TOKEN" =~ ^[A-Za-z0-9_-]{20,}$ ]] || { echo "CF_API_TOKEN has an unexpected format" >&2; exit 1; }

# cf METHOD PATH [JSON-BODY] -> prints response; fails on API errors.
cf() {
    local method=$1 path=$2 body=${3:-} out
    local args=(-sS --max-time 30 -X "$method" -K - -H 'Content-Type: application/json')
    [ -z "$body" ] || args+=(--data "$body")
    # The auth header goes in as a curl config on stdin, so the token never appears in argv.
    out=$(curl "${args[@]}" "$API$path" <<<"header = \"Authorization: Bearer $CF_API_TOKEN\"") \
        || { echo "request failed: $method $path" >&2; return 1; }
    jq -e '.success == true' >/dev/null <<<"$out" || {
        echo "Cloudflare API error on $method $path: $(jq -c '.errors' <<<"$out")" >&2; return 1; }
    printf '%s' "$out"
}

zone_id=$(cf GET "/zones?name=$CF_ZONE" | jq -r '.result[0].id // empty')
[ -n "$zone_id" ] || { echo "zone $CF_ZONE not found for this token (add the zone in Cloudflare first)" >&2; exit 1; }
echo "zone $CF_ZONE ($zone_id)$([ $DRY = 1 ] && echo ' [dry-run]')"

declare -A managed=()
while read -r type name content proxied ttl _; do
    [[ -z "$type" || "$type" == \#* ]] && continue
    fqdn=$name; [ "$name" = "@" ] && fqdn=$CF_ZONE
    [[ "$fqdn" == *.* && "$fqdn" == *"$CF_ZONE" ]] || fqdn="$name.$CF_ZONE"
    t=1; [ "$ttl" = auto ] || t=$ttl
    [ "$proxied" = true ] && [ "$t" != 1 ] && t=1   # proxied records are always "auto"
    managed["$type $fqdn"]=1
    want=$(jq -nc --arg type "$type" --arg name "$fqdn" --arg content "$content" \
        --argjson proxied "$proxied" --argjson ttl "$t" \
        '{type:$type,name:$name,content:$content,proxied:$proxied,ttl:$ttl}')
    cur=$(cf GET "/zones/$zone_id/dns_records?type=$type&name=$fqdn" | jq -c '.result[0] // empty')
    if [ -z "$cur" ]; then
        echo "create:    $type $fqdn -> $content (proxied=$proxied)"
        [ $DRY = 1 ] || cf POST "/zones/$zone_id/dns_records" "$want" >/dev/null
    elif [ "$(jq -r '.content' <<<"$cur")" != "$content" ] \
        || [ "$(jq -r '.proxied' <<<"$cur")" != "$proxied" ] \
        || [ "$(jq -r '.ttl' <<<"$cur")" != "$t" ]; then
        echo "update:    $type $fqdn -> $content (proxied=$proxied)"
        [ $DRY = 1 ] || cf PATCH "/zones/$zone_id/dns_records/$(jq -r '.id' <<<"$cur")" "$want" >/dev/null
    else
        echo "unchanged: $type $fqdn"
    fi
done <"$SITE_DIR/dns.records"

# Records in the zone that this file does not list.
cf GET "/zones/$zone_id/dns_records?per_page=200" | jq -r '.result[] | "\(.type) \(.name) \(.content)"' |
    while read -r type name content; do
        [ -n "${managed["$type $name"]:-}" ] || echo "unmanaged: $type $name -> $content"
    done

if [ -f "$SITE_DIR/cf-zone-settings" ]; then
    while read -r setting value _; do
        [[ -z "$setting" || "$setting" == \#* ]] && continue
        cur=$(cf GET "/zones/$zone_id/settings/$setting" | jq -r '.result.value')
        if [ "$cur" = "$value" ]; then
            echo "unchanged: setting $setting=$value"
        else
            echo "update:    setting $setting: $cur -> $value"
            [ $DRY = 1 ] || cf PATCH "/zones/$zone_id/settings/$setting" "$(jq -nc --arg v "$value" '{value:$v}')" >/dev/null
        fi
    done <"$SITE_DIR/cf-zone-settings"
fi
