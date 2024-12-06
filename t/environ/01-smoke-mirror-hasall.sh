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

FAKEURL="notexists${RANDOM}.com"

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$FAKEURL','','t','it','eu'"


$mc/sql "insert into server_capability_declaration(server_id, capability, enabled) select id, 'hasall', 't' from server where hostname = '${FAKEURL}'";

$mc/curl -Is /download/folder1/file1.1.dat.mirrorlist

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=it | grep -C10 302 | grep "${FAKEURL}"
$mc/curl /download/folder1/file1.1.dat.mirrorlist | grep "${FAKEURL}"
$mc/curl /download/folder1/file1.1.dat.metalink   | grep "${FAKEURL}"/folder1/file1.1.dat
# with pedantic we ignore it though
rc=0
$mc/curl -I /download/folder1/file1.1.dat?"COUNTRY=it&PEDANTIC=2" | grep "${FAKEURL}" || rc=$?
test $rc -gt 0

echo test LIMIT with meta4
test 3 == $($mc/curl /download/folder1/file1.1.dat.meta4 | grep location | wc -l)
test 2 == $($mc/curl /download/folder1/file1.1.dat.meta4?LIMIT=2 | grep location | wc -l)
test 1 == $($mc/curl /download/folder1/file1.1.dat.meta4?LIMIT=1 | grep location | wc -l)

echo test LIMIT with metalink
test 3 == $($mc/curl /download/folder1/file1.1.dat.metalink | grep location | wc -l)
test 2 == $($mc/curl /download/folder1/file1.1.dat.metalink?LIMIT=2 | grep location | wc -l)
test 1 == $($mc/curl /download/folder1/file1.1.dat.metalink?LIMIT=1 | grep location | wc -l)

echo test x-metalink-limit
test 2 == $($mc/curl -H 'x-metalink-limit: 2' /download/folder1/file1.1.dat.meta4 | grep location | wc -l)
test 1 == $($mc/curl -H 'x-metalink-limit: 1' /download/folder1/file1.1.dat.meta4 | grep location | wc -l)

echo success
