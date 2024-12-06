#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_PEDANTIC=2 \
            MIRRORCACHE_RECKLESS=1

$mc/start
$mc/status

ap7=$(environ ap7)

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

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
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
$mc/sql_test 3 == "select count(*) from minion_jobs where task='mirror_scan'"

# rescan and resync are not performed if folder wasn't requested (wanted) for 2 weeks
# Step1
# folder1, folder2 and folder3 are almost two weeks old since last access, so regular resync and rescan are still performed for them
# Step2
# the folders become 2*7*24*60*60 seconds old, but folder3 was requested recently, so only one regular resync and rescan is scheduled
# Step3
# folder2 gets accessed as well, so another resync and rescan are scheduled
# Step4 set wanted of folder1 to '2021-09-30' and confirm that wanted is updated promptly

S=5
S1=$((60-$S))
echo Step1
$mc/sql "update folder set wanted = CURRENT_TIMESTAMP(3) - interval '13 day'"
$mc/sql "update folder set wanted = wanted - interval '23 hour 59 minute $S1 second'"

$mc/sql_test 0 == "select count(*) from folder where sync_requested > sync_scheduled"
$mc/sql_test 0 == "select count(*) from folder where scan_requested > scan_scheduled"
$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/sql_test 0 == "select count(*) from folder where sync_requested > sync_scheduled"
$mc/sql_test 0 == "select count(*) from folder where scan_requested > scan_scheduled"
$mc/sql_test 6 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/sql_test 6 == "select count(*) from minion_jobs where task='mirror_scan'"

echo Step2
sleep $S
$mc/sql_test 0 == "select count(*) from folder where wanted > now() - interval '14 day'"
$mc/curl -I /download/folder3/file1.1.dat | grep 302

# $mc/sql "select path, wanted,  now() - 2*7*24*60* interval '60 second', now() - 2*7*24*60* interval '60 second' + interval '$S second' from folder"
# $mc/sql_test 1 == "select count(*) from folder where wanted > now() - 2*7*24*60* interval '60 second'"

# $mc/sql -n -e "select * from folder" mc_test
# $mc/sql_test 1 == "select count(*) from folder where wanted > date_sub(now(), interval 14 day)"

$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/sql_test 0 == "select count(*) from folder where sync_requested > sync_scheduled"
$mc/sql_test 0 == "select count(*) from folder where scan_requested > scan_scheduled"
$mc/sql_test 7 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/sql_test 7 == "select count(*) from minion_jobs where task='mirror_scan'"

echo Step3
$mc/curl -I /download/folder3/file1.1.dat

$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/sql_test 0 == "select count(*) from folder where sync_requested > sync_scheduled"
$mc/sql_test 0 == "select count(*) from folder where scan_requested > scan_scheduled"
$mc/sql_test 8 == "select count(*) from minion_jobs where task='folder_sync'"
$mc/sql_test 8 == "select count(*) from minion_jobs where task='mirror_scan'"

echo Step4
$mc/sql "update folder set wanted = '2019-09-30' where path = '/folder1'"
$mc/curl -I /download/folder1/file1.1.dat | grep 302
$mc/sql "select wanted from folder where path = '/folder1'"
$mc/sql_test 1 = "select 1 from folder where path = '/folder1' and wanted > now() - interval '1 minute'"

