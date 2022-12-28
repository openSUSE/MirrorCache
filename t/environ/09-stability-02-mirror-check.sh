#!lib/test-in-container-environ.sh
set -ex

MIRROR_CHECK_DELAY=2

mc=$(environ mc $(pwd))
$mc/gen_env MIRRORCACHE_RECKLESS=0 MIRRORCACHE_MIRROR_CHECK_DELAY=$MIRROR_CHECK_DELAY
$mc/start
$mc/status

ap7=$(environ ap7)

for x in $mc $ap7; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

$mc/curl -I /download/folder1/file1.1.dat

# $mc/backstage/job mirror_probe
# $mc/backstage/job folder_sync_schedule_from_misses
# $mc/backstage/job folder_sync_schedule

id1=$($mc/backstage/job -e folder_sync -a '["/folder1"]')
id1=$($mc/backstage/job -e mirror_scan -a '["/folder1"]')
$mc/backstage/shoot

# check redirection works
$mc/curl -I /download/folder1/file1.1.dat | grep -C20 302 | grep $($ap7/print_address)

# now remove the file shut down ap7 and call mirror_check
rm $ap7/dt/folder1/file1.1.dat

id=$($mc/backstage/job -e mirror_check_from_stat)
$mc/backstage/shoot
$mc/backstage/job -e mirror_scan_schedule -a '["once"]'
$mc/backstage/shoot
# check a new mirror_scan job was scheduled
$mc/sql_test 1 == "select count(*) from minion_jobs where id>$id and task = 'mirror_scan'"

# no redirect anymore
$mc/curl -I /download/folder1/file1.1.dat | grep -C20 '200 OK'

# restore deleted file from mirror
touch $ap7/dt/folder1/file1.1.dat
# $mc/curl -i /download/folder1/file1.1.dat.metalink | grep '200 OK' # | grep $($ap7/print_address)
sleep $MIRROR_CHECK_DELAY

$mc/backstage/shoot
echo check no new mirror_scan job was scheduled

$mc/sql_test nope == "select case when scan_scheduled < scan_requested then 'requested' else 'nope' end from folder where id = 1"

id1=$($mc/backstage/job -e mirror_scan -a '["/folder1"]')
$mc/backstage/shoot

sleep $MIRROR_CHECK_DELAY
$mc/backstage/shoot

echo no jobs after the one we scheduled explicitly
$mc/sql_test 0 == "select count(*) from minion_jobs where id>$id1 and task = 'mirror_scan'"

echo shoot mirrorcheck_from_scan again, but bring ap7 down - no new scan should happen because no new stat entry
$ap7/stop
sleep $MIRROR_CHECK_DELAY
$mc/backstage/shoot

$mc/sql_test nope == "select case when scan_scheduled < scan_requested then 'requested' else 'nope' end from folder where id = 1"

echo now let stat have one more entry and the job will schedule
$mc/curl -I /download/folder1/file1.1.dat | grep -C20 302 | grep $($ap7/print_address)

$ap7/start
sleep $MIRROR_CHECK_DELAY
rm $ap7/dt/folder1/file1.1.dat
$mc/sql "select * from folder"
$mc/backstage/shoot
$mc/sql "select * from folder"

$mc/sql_test requested == "select case when scan_scheduled < scan_requested then 'requested' else 'nope' end from folder where id = 1"
echo success
