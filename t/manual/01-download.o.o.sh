#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_RECKLESS=0 \
    MIRRORCACHE_ROOT=http://download.opensuse.org \
    MIRRORCACHE_REDIRECT=downloadcontent.opensuse.org \
    MIRRORCACHE_HYPNOTOAD=1 \
    MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule cleanup stat_agg_schedule mirror_check_from_stat'" \
    MIRRORCACHE_TOP_FOLDERS="'debug distribution tumbleweed factory repositories'" \
    MIRRORCACHE_AUTH_URL=https://www.opensuse.org/openid/user/ \
    MIRRORCACHE_TRUST_AUTH=127.0.0.2 \
    MIRRORCACHE_PROXY_URL=http://127.0.0.1:3110 \
    MIRRORCACHE_BACKSTAGE_WORKERS=32

    

$mc/start
$mc/backstage/start
$mc/db/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-eu.sql mc_test

$mc/backstage/job -e folder_tree -a '["/distribution"]'
$mc/backstage/job -e folder_tree -a '["/tumbleweed"]'
