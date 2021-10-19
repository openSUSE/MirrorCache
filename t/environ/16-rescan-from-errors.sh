#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0
MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0
MIRRORCACHE_RESCAN_INTERVAL=$((7 * 24 * 60 * 60)) # set one week to avoid automatic rescan

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=$MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT \
            MIRRORCACHE_RESCAN_INTERVAL=$MIRRORCACHE_RESCAN_INTERVAL \
            MIRRORCACHE_PEDANTIC=1 \
            MIRRORCACHE_RECKLESS=0

$mc/start
$mc/status

ap7=$(environ ap7)

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

for x in $mc $ap7; do
    mkdir -p $x/dt/folder{1,2,3}
    echo $x/dt/folder{1,2,3}/file1.1.dat | xargs -n 1 touch
done

$ap7/start

for x in {1,2,3} ; do
    $mc/backstage/job -e folder_sync -a '["/folder'$x'"]'
done

$mc/backstage/shoot
$mc/sql_test 3 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
$mc/sql_test 3 == "select count(*) from minion_jobs where task='mirror_scan'"

$mc/sql "update file set dt = now() - interval '1 month'"  # set old date, otherwise it will interfere with rescan login in Stat.pm


# handling of mirror errors:
# if file is not found on mirror anymore - schedule resync unless it was performed up to 4 hour ago, schedule rescan unless it was performed up to 4 hour ago
# if file on mirror has different size and newer timestamp - schedule resync unless it was performed up to 15 min ago
# if file on mirror has different size and older timestamp - schedule resync unless it was performed up to 24 hours ago

# not covered in test:
# if file on mirror has different timestamp and cannot check size - do nothing for now
# if file on mirror has different size and cannot check timestamp - schedule resync unless it was performed up to 4 hour ago, schedule rescan unless it was performed up to 4 hour ago

rm $ap7/dt/folder1/file1.1.dat
echo 1 > $ap7/dt/folder2/file1.1.dat
echo 1 > $ap7/dt/folder3/file1.1.dat && touch -d '-1 day' $ap7/dt/folder3/file1.1.dat

S=15
$mc/sql "update folder set scan_last = now() - interval '4 hour'    + interval '$S second' where path = '/folder1'"
$mc/sql "update folder set scan_last = now() - interval '15 minute' + interval '$S second' where path = '/folder2'"
$mc/sql "update folder set scan_last = now() - interval '24 hour'   + interval '$S second' where path = '/folder3'"

$mc/sql "update folder set sync_last = scan_last - interval '5 second'"
$mc/sql "update folder set scan_requested = scan_last - interval '2 second', scan_scheduled = scan_last - interval '1 second', sync_requested = sync_last - interval '2 second', sync_scheduled = sync_last - interval '1 second'"

$mc/sql 'select * from folder'

for x in {1,2,3} ; do
    $mc/curl -I /download/folder$x/file1.1.dat?PEDANTIC=0 | grep '302 Found'
    $mc/curl -I /download/folder$x/file1.1.dat | grep '200 OK'
done

$mc/backstage/job mirror_scan_schedule_from_path_errors
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# no new jobs were scheduled yet
$mc/sql_test 3 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/sql_test 3 == "select count(*) from minion_jobs where task='mirror_scan'"

sleep $S

for x in {1,2,3} ; do
    $mc/curl -I /download/folder$x/file1.1.dat | grep '200 OK'
done

$mc/backstage/job mirror_scan_schedule_from_path_errors
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# no new jobs were scheduled yet
$mc/sql_test 6 == "select count(*) from minion_jobs where task='folder_sync'"
# only folder3 must cause mirror scan from path_errors, but folder1 will be rescanned from Stat.pm
$mc/sql_test 5 == "select count(*) from minion_jobs where task='mirror_scan'"
