#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0
$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap8/start

sleep 0.1

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove a file from one mirror
rm $ap8/dt/folder1/file2.1.dat

# force scan
$mc/curl -I /download/folder1/file2.1.dat

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# update dt column to make entries look older
$mc/sql "update folder_diff set dt = dt - interval '5 day'"
$mc/sql "update server_capability_check set dt = dt - interval '14 day' where server_id = 1"

# now add new files on some mirrors to generate diff
touch {$mc,$ap7}/dt/folder1/file3.1.dat
touch {$mc,$ap8}/dt/folder1/file4.dat

# force rescan
$mc/curl -Is /download/folder1/file3.1.dat

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

test 4 == $($mc/db/sql "select count(*) from folder_diff")
test 4 == $($mc/db/sql "select count(*) from folder_diff_file")
test 4 == $($mc/db/sql "select count(*) from server_capability_check")
test 8 == $($mc/db/sql "select count(*) from server_stability")
test 2 == $($mc/db/sql "select count(*) from server_stability where capability = 'http'  and rating > 0")
test 2 == $($mc/db/sql "select count(*) from server_stability where capability = 'https' and rating = 0")
test 2 == $($mc/db/sql "select count(*) from server_stability where capability = 'ipv4'  and rating > 0")
test 2 == $($mc/db/sql "select count(*) from server_stability where capability = 'ipv6'  and rating = 0")

# update dt to look older and save number of audit events
$mc/sql "update audit_event set dt = dt - interval '50 day'"
audit_events=$($mc/sql "select count(*) from audit_event")

# run cleanup job
$mc/backstage/job cleanup
$mc/backstage/shoot

# test for reduced number of rows
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 3 == $($mc/db/sql "select count(*) from folder_diff_file")
# server_id had too old checks and they were cleaned in the cleanup job
test 2 == $($mc/db/sql "select count(*) from server_capability_check")
test $audit_events -gt $($mc/db/sql "select count(*) from audit_event")
echo success
