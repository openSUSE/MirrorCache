#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
    MIRRORCACHE_ROOT="'$mc/dt/root1:root1.com:root1.vpn|$mc/dt/root2:root2.com:root2.vpn|$mc/dt/root3:root3.com:root3.vpn'"

mkdir -p $mc/dt/root1
mkdir -p $mc/dt/root2
mkdir -p $mc/dt/root3

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

mkdir $mc/dt/root1/folder1
echo $mc/dt/root1/folder1/{file1.1,file2.1}.dat | xargs -n 1 touch

mkdir $mc/dt/root2/folder2
echo $mc/dt/root2/folder2/{file1.1,file2.1}.dat | xargs -n 1 touch

mkdir $mc/dt/root3/folder3
echo $mc/dt/root3/folder3/{file1.1,file2.1}.dat | xargs -n 1 touch

for x in $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat


$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -Is /download/folder1/file1.1.dat | grep -i location: | grep root1.com
$mc/curl -H 'X-Forwarded-For: 10.0.0.1' -Is /download/folder1/file1.1.dat | grep -i location: | grep root1.vpn

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/curl /download/folder1/ | grep file1.1.dat
# check redirect is correct
$mc/curl -Is /download/folder1 | grep -i 'Location: /download/folder1/'

# only ap7 is in US
$mc/curl -Is /download/folder1/file1.1.dat | grep -C10 302 | grep "$($ap7/print_address)"

###################################
# test files are removed properly
rm $mc/dt/root1/folder1/file1.1.dat

# resync the folder
$mc/backstage/job folder_sync_schedule
$mc/backstage/job -e mirror_probe -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -s /download/folder1/ | grep file1.1.dat || :
if $mc/curl -s /download/folder1/ | grep file1.1.dat ; then
    fail file1.1.dat was deleted
fi

$mc/curl -H "Accept: */*, application/metalink+xml" -s /download/folder1/file2.1.dat | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'
$mc/curl -s /download/folder1/file2.1.dat.metalink | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'

$mc/curl -s '/download/folder1/file2.1.dat?mirrorlist' | grep 'http://127.0.0.1:1304/folder1/file2.1.dat'
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | grep 'http://127.0.0.1:1304/folder1/file2.1.dat'
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | tidy --drop-empty-elements no
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | grep "Origin: " | grep root1.com/folder1/file2.1.dat
$mc/curl -s '/download/folder1/file2.1.dat.metalink'   | grep "origin"   | grep $($mc/print_address)/download/folder1/file2.1.dat

# test metalink and mirrorlist when file is unknow yet
$mc/curl /download/folder3/file1.1.dat.metalink   | grep 'retry later'
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'retry later'

sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
sleep 0.1
$mc/backstage/shoot
rc=0
$mc/curl /download/folder3/file1.1.dat.metalink   | grep 'retry later' || rc=$?
test $rc -gt 0
$mc/curl /download/folder3/file1.1.dat.metalink   | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder3/file1.1.dat</url>'
$mc/curl /download/folder3/file1.1.dat.metalink   | grep 'root3.com'
$mc/curl /download/folder3/file1.1.dat.mirrorlist   | grep 'root3.com'

rc=0
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'retry later' || rc=$?
test $rc -gt 0
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'http://127.0.0.1:1304/folder3/file1.1.dat'

$mc/curl -s /download/ | grep -C10 folder1 | grep -C10 folder2 | grep folder3
