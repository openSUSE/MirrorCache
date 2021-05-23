#!lib/test-in-container-environ.sh
set -euxo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL=1
$mc/gen_env MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses cleanup stat_agg_schedule'" \
            MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL=$MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL

$mc/start

test 5 == $($mc/db/sql "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'")

$mc/stop

# let's assume some jobs were killed
$mc/db/sql "delete from minion_jobs where ctid IN (SELECT ctid FROM minion_jobs ORDER BY random() LIMIT 3)"

test 2 == $($mc/db/sql "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'")

$mc/start

sleep $MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL
sleep 1
test 5 == $($mc/db/sql "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'")
$mc/db/sql "delete from minion_jobs where ctid IN (SELECT ctid FROM minion_jobs ORDER BY random() LIMIT 3)"
sleep $MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL
sleep 1

test 5 == $($mc/db/sql "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'")
