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

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

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
test 1 == $($mc/db/sql "select count(*) from server_capability_check where server_id=1 and capability='http'")

# add 4 more failures from the past into DB
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'http', min(dt) - interval '15 minute'  from server_capability_check"
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'http', min(dt) - interval '15 minute'  from server_capability_check"
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'http', min(dt) - interval '15 minute'  from server_capability_check"
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'http', min(dt) - interval '15 minute'  from server_capability_check"
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'https', min(dt) - interval '15 minute'  from server_capability_check"
$mc/sql "insert into server_capability_check(server_id, capability, dt) select 1, 'https', min(dt) - interval '15 minute'  from server_capability_check"

# make sure we added properly
test 5 == $($mc/db/sql "select count(*) from server_capability_check where server_id=1 and capability='http'")
# we have inserted 2, plus 2 from manual runs of 'mirror_probe' job, plus 1 'mirror_probe' was scheduled from 'mirror_scan'
test 5 == $($mc/db/sql "select count(*) from server_capability_check where server_id=1 and capability='https'")

$mc/backstage/job -e mirror_force_downs
$mc/backstage/shoot

test 1 == $($mc/db/sql "select count(*) from server_capability_force where server_id=1 and capability='https'")
test 1 == $($mc/db/sql "select count(*) from server_capability_force where server_id=1 and capability='http'")

# age entry, so next job will consider it
$mc/sql "update server_capability_force set dt = dt - interval '3 hour'"

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
