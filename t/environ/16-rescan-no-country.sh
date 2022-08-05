#!lib/test-in-container-environ.sh
set -ex

# This test is identical to 16-rescan, just it has hit in another country instead of miss

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

MIRRORCACHE_RESCAN_INTERVAL=$((7 * 24 * 60 * 60)) # set one week to avoid automatic rescan

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_RESCAN_INTERVAL=$MIRRORCACHE_RESCAN_INTERVAL \
            MIRRORCACHE_RECKLESS=0

$mc/start
$mc/status

ap8=$(environ ap8)
$ap8/start
$ap8/status

for x in $mc $ap8; do
    mkdir -p $x/dt/folder{1,2,3,4,5,6}
    echo $x/dt/folder{2,3,4,5,6}/file1.1.dat | xargs -n 1 touch
done

for x in {1,2,3,4,5,6} ; do
    $mc/backstage/job -e folder_sync -a '["/folder'$x'"]'
done
# folder1 must have some file, so scan is triggered
touch $mc/dt/folder1/x

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

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
S1=$((60-$S))
$mc/sql "update file set dt = now() - interval '1 hour' where folder_id in (select id from folder where path = '/folder2')"
$mc/sql "update file set dt = now() - interval '4 hour' where folder_id in (select id from folder where path = '/folder3')"
$mc/sql "update file set dt = now() - interval '24 hour' where folder_id in (select id from folder where path = '/folder4')"
$mc/sql "update file set dt = now() - interval '72 hour' where folder_id in (select id from folder where path = '/folder5')"

# should cover both Pg and MariaDB
$mc/sql "update file set dt = dt + 2* interval '$S second'" || \
  $mc/sql "update file set dt = date_add(dt, interval 2*$S second)"

$mc/sql "update file set dt = dt - interval '72 hour' where folder_id in (select id from folder where path = '/folder6')"

touch $mc/dt/folder1/file1.1.dat
cp $mc/dt/folder1/file1.1.dat $ap8/dt/folder1/file1.1.dat

$mc/sql "update folder set scan_last = now() - interval '14 minute $S1 second' where path = '/folder1'"
$mc/sql "update folder set scan_last = now() - interval '29 minute $S1 second' where path = '/folder2'"
$mc/sql "update folder set scan_last = now() - interval '59 minute $S1 second' where path = '/folder3'"
$mc/sql "update folder set scan_last = now() - interval '3 hour 59 minute $S1 second' where path = '/folder4'"
$mc/sql "update folder set scan_last = now() - interval '7 hour 59 minute $S1 second' where path = '/folder5'"
$mc/sql "update folder set scan_last = now() - interval '24 hour' where path = '/folder6'"

$mc/sql "update folder set scan_requested = scan_last - interval '2 second', scan_scheduled = scan_last - interval '1 second'"
$mc/sql 'select * from folder'


$mc/curl -I /download/folder1/file1.1.dat | grep '200 OK'

for x in {2,3,4,5,6} ; do
    $mc/curl -IL /download/folder$x/file1.1.dat | grep -A20 '302 Found' | grep '200 OK'
done

$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

echo folder1 was resynced because it got new file
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"
echo still nothing was scheduled, except folder1 which got new files and folder6 which reaches max refresh time 24 hours
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
    $mc/curl -IL /download/folder$x/file1.1.dat | grep -A20 '302 Found' | grep '200 OK'
done

$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# Now all fodlers are scanned twice
$mc/sql_test 12 == "select count(*) from minion_jobs where task='mirror_scan'"
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"

echo only first request was miss
$mc/sql_test 1 == "select count(*) from stat where mirror_id < 1"
echo all other requests are hits for the mirror
$mc/sql_test 11 == "select count(*) from stat where mirror_id = 1"

echo success
