#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

export MIRRORCACHE_PERMANENT_JOBS='folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses cleanup stat_agg_schedule'

mc9*/start.sh

test 5 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'" mc_test)

mc9*/stop.sh

# let's assume some jobs were killed
pg9*/sql.sh -t -c "delete from minion_jobs where ctid IN (SELECT ctid FROM minion_jobs ORDER BY random() LIMIT 3)" mc_test

test 2 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'" mc_test)
export MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL=1
mc9*/start.sh

sleep 2
test 5 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'" mc_test)
pg9*/sql.sh -t -c "delete from minion_jobs where ctid IN (SELECT ctid FROM minion_jobs ORDER BY random() LIMIT 3)" mc_test
sleep 2
test 5 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where state in ('active', 'inactive') and task not like 'mirror_force%'" mc_test)

