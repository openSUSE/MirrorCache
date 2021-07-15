#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
            MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

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

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove a file from one mirror
rm $ap8/dt/folder1/file2.1.dat

# force scan
$mc/curl -I /download/folder1/file2.1.dat
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

# update dt column to make entries look older
$mc/db/sql "update folder_diff set dt = dt - interval '5 day'"
$mc/db/sql "update server_capability_check set dt = dt - interval '5 day' where server_id = 1"

# now add new files on some mirrors to generate diff
touch {$mc,$ap7}/dt/folder1/file3.1.dat
touch {$mc,$ap8}/dt/folder1/file4.dat

# force rescan
$mc/curl -Is /download/folder1/file3.1.dat
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot

test 4 == $($mc/db/sql "select count(*) from folder_diff")
test 4 == $($mc/db/sql "select count(*) from folder_diff_file")
test 8 == $($mc/db/sql "select count(*) from server_capability_check")

# update dt to look older and save number of audit events
$mc/db/sql "update audit_event set dt = dt - interval '50 day'"
audit_events=$($mc/db/sql "select count(*) from audit_event")

# run cleanup job
$mc/backstage/job cleanup
$mc/backstage/shoot

# test for reduced number of rows
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 3 == $($mc/db/sql "select count(*) from folder_diff_file")
test 4 == $($mc/db/sql "select count(*) from server_capability_check")
test $audit_events -gt $($mc/db/sql "select count(*) from audit_event")
