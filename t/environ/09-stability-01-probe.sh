#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.dat

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/curl -I /download/folder1/file1.dat

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

# check redirection works
$mc/curl -I /download/folder1/file1.dat | grep 302

# now shut down ap7 and do probe
$ap7/stop
$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot

# log current audit_event count
cnt="$($mc/db/sql "select count(*) from audit_event")"

# make sure now it redirects to ap8
$mc/curl -I /download/folder1/file2.dat | grep $($ap8/print_address)

# audit event shouldn't contain recent mirror_probe event, becuase we know that ap7 is not preferable because of recent probe error
test 0 == $($mc/db/sql "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt")

# now shut down ap8 and start ap7, then probe mirrors explicitly
$ap8/stop
$ap7/start
$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot

cnt="$($mc/db/sql 'select count(*) from audit_event')"
# make sure now it redirects to ap7
$mc/curl -I /download/folder1/file2.dat | grep $($ap7/print_address)
# audit event shouldn't contain recent mirror_probe event, becuase we know that ap7 is not preferable because of recent probe error
test 0 == $($mc/db/sql "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt")
