#!lib/test-in-container-environ.sh
set -euxo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL=1
$mc/gen_env MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses cleanup stat_agg_schedule'" \
            MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL=$MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL

$mc/start

$mc/sql_test 5 == "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'"

$mc/stop

# let's assume some jobs were killed
$mc/sql "delete from minion_jobs ORDER BY rand() LIMIT 3"

$mc/sql_test 2 == "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'"

$mc/start

sleep $MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL
sleep 1
$mc/sql_test 5 == "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'"
$mc/sql "delete from minion_jobs ORDER BY rand() LIMIT 3"
sleep $MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL
sleep 1

$mc/sql_test 5 == "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'"
