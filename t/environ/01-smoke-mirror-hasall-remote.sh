#!lib/test-in-container-environ.sh
set -ex

FAKEURL="notexists${RANDOM}.com"
FAKEURL2="notexists2${RANDOM}.com"

ap9=$(environ ap9)

mc=$(environ mc $(pwd))

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_METALINK_GREEDY=3 \
    MIRRORCACHE_REDIRECT=$FAKEURL2

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done
# this file doesnt exist on mirrors
touch $ap9/dt/folder1/file3.1.dat

$ap9/start
$ap9/curl /folder1/ | grep file1.1.dat

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat
rm $ap7/dt/folder1/file2.1.dat # remove a file from ap7

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
$mc/curl /download/folder1/file1.1.dat.metalink | grep "${FAKEURL2}"/folder1/file1.1.dat
# with pedantic we ignore it though
rc=0
$mc/curl -I /download/folder1/file1.1.dat?"COUNTRY=it&PEDANTIC=2" | grep "${FAKEURL}" || rc=$?
test $rc -gt 0

echo When METALINK_GREEDY is set, REDIRECT url will appear only as comment if mirror count exceeds value of METALINK_GREEDY
$mc/curl /download/folder1/file1.1.dat.metalink | grep -A1 'File origin' | grep '<!-- http://'${FAKEURL2}'/folder1/file1.1.dat -->'

echo for file2 REDIRECT still appears in metalink from folder2, because mirror count doesnt exceed value of METALINK_GREEDY
$mc/curl /download/folder1/file2.1.dat.metalink | grep -A1 'File origin' | grep '<url type="http" location="" preference="98">http://'${FAKEURL2}'/folder1/file2.1.dat</url>'

$mc/curl /download/folder1/file2.1.dat.meta4 | grep -A1 'File origin' | grep '<url location="" priority="3">http://'${FAKEURL2}'/folder1/file2.1.dat</url>'

$mc/curl /download/folder1/file3.1.dat.meta4 | grep -A1 'File origin' | grep '<url location="" priority="2">http://'${FAKEURL2}'/folder1/file3.1.dat</url>'

echo success
