#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_RECKLESS=0 \
    MIRRORCACHE_ROOT=$mc/dt \
    MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule cleanup stat_agg_schedule mirror_check_from_stat'" \
    MIRRORCACHE_BACKSTAGE_WORKERS=4 \
    MIRRORCACHE_HASHES_QUEUE=default \
    MIRRORCACHE_HASHES_COLLECT=1

$mc/start
$mc/backstage/start

echo Service started, press Ctrl+C to finish test
sleep 10000 0
