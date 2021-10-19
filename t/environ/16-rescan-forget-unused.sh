#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0
MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=$MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT \
            MIRRORCACHE_PEDANTIC=1 \
            MIRRORCACHE_RECKLESS=1

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
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
$mc/sql_test 3 == "select count(*) from minion_jobs where task='mirror_scan'"

# rescan and resync are not performed if folder wasn't requested (wanted) for 2 weeks
# Step1
# folder1, folder2 and folder3 are almost two weeks old since last access, so regular resync and rescan are still performed for them
# Step2
# the folders become 2 weeks old, but folder3 was requested recently, so only one regular resync and rescan is scheduled
# Step3
# folder2 gets accessed as well, so another resync and rescan are scheduled

S=5
echo Step1
$mc/sql "update folder set wanted = now() - interval '2 week' + interval '$S second'"

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
$mc/sql_test 0 == "select count(*) from folder where wanted > now() - interval '2 week'"
$mc/curl -I /download/folder3/file1.1.dat | grep 302

$mc/sql "select path, wanted,  now() - interval '2 week', now() - interval '2 week' + interval '$S second' from folder"
$mc/sql_test 1 == "select count(*) from folder where wanted > now() - interval '2 week'"


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
