#!lib/test-in-container-environ.sh
set -ex

# To register an OAuth2 client for testing on id.opensuse.org (RFC 7591):
#
#   curl -sL -X POST https://id.opensuse.org/openidc/Registration \
#     -H "Content-Type: application/json" \
#     -d '{
#       "client_name": "MirrorCache Manual Test",
#       "redirect_uris": ["https://127.0.0.1:3110/login"],
#       "token_endpoint_auth_method": "client_secret_post"
#     }'
#
# Then run this script with the returned client_id and client_secret:
#
#   MIRRORCACHE_OAUTH2_KEY="<client_id>" \
#   MIRRORCACHE_OAUTH2_SECRET="<client_secret>" \
#   bash t/manual/04-oauth2-opensuse.sh

mc=$(environ mc $(pwd))

PROXY_URL=${MIRRORCACHE_PROXY_URL:-https://127.0.0.1:3110}

$mc/gen_env MIRRORCACHE_RECKLESS=0 \
    MIRRORCACHE_ROOT=http://download.opensuse.org \
    MIRRORCACHE_REDIRECT=downloadcontent.opensuse.org \
    MIRRORCACHE_HYPNOTOAD=0 \
    MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule cleanup stat_agg_schedule mirror_check_from_stat'" \
    MIRRORCACHE_TOP_FOLDERS="'debug distribution tumbleweed factory repositories update'" \
    MIRRORCACHE_PROXY_URL="$PROXY_URL" \
    MIRRORCACHE_BRANDING=openSUSE \
    MIRRORCACHE_BACKSTAGE_WORKERS=32 \
    MOJO_LISTEN=https://*:3110

echo "export MIRRORCACHE_INI=$mc/conf.ini" >> $mc/conf.env

# Allow mc/status to check reachability over HTTPS with self-signed certificate
sed -i 's|http://|https://|g; s|curl -sI|curl -skI|g' $mc/status 2>/dev/null || true

cat << EOF >> $mc/conf.ini
[auth]
method = OAuth2

[oauth2]
provider = custom
authorize_url = https://id.opensuse.org/openidc/Authorization?response_type=code
token_url = https://id.opensuse.org/openidc/Token
user_url = https://id.opensuse.org/openidc/UserInfo
token_scope = openid profile email
token_label = Bearer
id_from = sub
nickname_from = nickname
unique_name = opensuse
key = ${MIRRORCACHE_OAUTH2_KEY:-myopensusekey}
secret = ${MIRRORCACHE_OAUTH2_SECRET:-mysecretsecret}
EOF

$mc/start
$mc/backstage/start
$mc/db/sql -f dist/salt/mirrors-eu.sql mc_test
