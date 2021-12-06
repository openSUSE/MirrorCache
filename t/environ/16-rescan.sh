#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

MIRRORCACHE_RESCAN_INTERVAL=$((7 * 24 * 60 * 60)) # set one week to avoid automatic rescan

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_RESCAN_INTERVAL=$MIRRORCACHE_RESCAN_INTERVAL \
            MIRRORCACHE_RECKLESS=0

$mc/start
$mc/status

mkdir -p $mc/dt/folder{1,2,3,4,5,6}
echo $mc/dt/folder{2,3,4,5,6}/file1.1.dat | xargs -n 1 touch

for x in {1,2,3,4,5,6} ; do
    $mc/backstage/job -e folder_sync -a '["/folder'$x'"]'
done
# folder1 must have some file, so scan is triggered
touch $mc/dt/folder1/x

$mc/backstage/shoot
$mc/sql_test 6 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
$mc/sql_test 6 == "select count(*) from minion_jobs where task='mirror_scan'"

# handling of misses:
# if file is unknown - schedule resync unless it was performed up to 15 min ago
# if file is earlier than 1h  - schedule rescan unless it was performed up to 30 min ago
# if file is earlier than 4h  - schedule rescan unless it was performed up to 1 hour ago
# if file is earlier than 24h - schedule rescan unless it was performed up to 4 hours ago
# if file is earlier than 72h - schedule rescan unless it was performed up to 8 hours ago
# if file is older than 72 hours - schedule rescan unless it was performed up to 1 24 hours ago

S=10
$mc/sql "update file set dt = now() -  1 * interval '3600 second' where folder_id in (select id from folder where path = '/folder2')"
$mc/sql "update file set dt = now() -  4 * interval '3600 second' where folder_id in (select id from folder where path = '/folder3')"
$mc/sql "update file set dt = now() - 24 * interval '3600 second' where folder_id in (select id from folder where path = '/folder4')"
$mc/sql "update file set dt = now() - 72 * interval '3600 second' where folder_id in (select id from folder where path = '/folder5')"

$mc/sql "update file set dt = dt + 2*interval '$S second'"

$mc/sql "update file set dt = dt - 72 * interval '3600 second' where folder_id in (select id from folder where path = '/folder6')"

touch $mc/dt/folder1/file1.1.dat
$mc/sql "update folder set scan_last = now() - interval '15 minute' + interval '$S second' where path = '/folder1'"
$mc/sql "update folder set scan_last = now() - interval '30 minute' + interval '$S second' where path = '/folder2'"
$mc/sql "update folder set scan_last = now() - interval '1 hour'    + interval '$S second' where path = '/folder3'"
$mc/sql "update folder set scan_last = now() - interval '4 hour'    + interval '$S second' where path = '/folder4'"
$mc/sql "update folder set scan_last = now() - interval '8 hour'    + interval '$S second' where path = '/folder5'"
$mc/sql "update folder set scan_last = now() - interval '24 hour'                          where path = '/folder6'"

$mc/sql "update folder set scan_requested = scan_last - interval '2 second', scan_scheduled = scan_last - interval '1 second'"
$mc/sql 'select * from folder'


for x in {1,2,3,4,5,6} ; do
    $mc/curl -I /download/folder$x/file1.1.dat | grep '200 OK'
done

$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# folder1 was resynced because it got new file
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"
# still nothing was scheduled, except folder1 which got new files and folder6 which reaches max refresh time 24 hours
$mc/sql_test 8 == "select count(*) from minion_jobs where task='mirror_scan'"

sleep $S
# c/sql "update folder set scan_last = scan_last + interval '$S second'"
$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# no new jobs were submitted yet
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/sql_test 8 == "select count(*) from minion_jobs where task='mirror_scan'"

for x in {1,2,3,4,5,6} ; do
    $mc/curl -I /download/folder$x/file1.1.dat | grep '200 OK'
done

$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# Now all fodlers are scanned twice
$mc/sql_test 12 == "select count(*) from minion_jobs where task='mirror_scan'"
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"
