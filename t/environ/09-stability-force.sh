#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/curl -I /download/folder1/file1.1.dat

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# check redirection works
$mc/curl -I /download/folder1/file1.1.dat | grep 302

# now shut down ap7 and do probe
$ap7/stop
$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot

# check that ap7 is marked correspondingly in server_capability_check
test 1 == $($mc/db/sql "select sum(case when success then 0 else 1 end) from server_capability_check where server_id=1 and capability='http'")

# add 4 more failures from the past into DB
$mc/db/sql "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'"
$mc/db/sql "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'"
$mc/db/sql "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'"
$mc/db/sql "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'"

# make sure we added properly
test 5 == $($mc/db/sql "select sum(case when success then 0 else 1 end) from server_capability_check where server_id=1 and capability='http'")

$mc/backstage/job -e mirror_force_downs
$mc/backstage/shoot

test 1 == $($mc/db/sql "select count(*) from server_capability_force where server_id=1 and capability='http'")

# age entry, so next job will consider it
$mc/db/sql "update server_capability_force set dt = dt - interval '3 hour'"

# now start back ap7 and shut down ap8 but ap7 is not redirected, because it is force disabled
$ap7/start
$ap8/stop
$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot

rc=0
$mc/curl -I /download/folder1/file1.1.dat | grep $($ap7/print_address) || rc=$?
test $rc -gt 0


# now scan those mirrors which were force disabled
$mc/backstage/job -e mirror_force_ups
$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot

# ap7 now should serve the request
$mc/curl -I /download/folder1/file1.1.dat | grep $($ap7/print_address)
