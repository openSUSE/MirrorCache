#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_RECKLESS=0 \
    MIRRORCACHE_ROOT=http://download.opensuse.org \
    MIRRORCACHE_REDIRECT=downloadcontent.opensuse.org \
    MIRRORCACHE_HYPNOTOAD=0 \
    MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule cleanup stat_agg_schedule mirror_check_from_stat'" \
    MIRRORCACHE_TOP_FOLDERS="'debug distribution tumbleweed factory repositories update'" \
    MIRRORCACHE_PROXY_URL=http://127.0.0.1:3110 \
    MIRRORCACHE_BRANDING=openSUSE \
    MIRRORCACHE_BACKSTAGE_WORKERS=32

echo "export MIRRORCACHE_INI=$mc/conf.ini" >> $mc/conf.env

cat << EOF >> $mc/conf.ini
[auth]
method = OAuth2

[oauth2]
provider = custom
authorize_url = https://id.suse.com/application/o/authorize/?response_type=code
token_url = https://id.suse.com/application/o/token/
user_url = https://id.suse.com/application/o/userinfo/
token_scope = email profile openid sub communityUidAsopenId
token_label = Bearer
id_from = communityUidAsopenId
nickname_from = sub
unique_name = suseid
key = ${MIRRORCACHE_OAUTH2_KEY:-mysercretkey}
secret = ${MIRRORCACHE_OAUTH2_SECRET:-mysecretsecret}
EOF

$mc/start
$mc/backstage/start
$mc/db/sql -f dist/salt/mirrors-eu.sql mc_test
