#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
$mc/gen_env MIRRORCACHE_ROOT_COUNTRY=us
$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

mkdir -p $mc/dt/{folder1,folder2,folder3}
echo $mc/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch

mkdir -p $mc/dt/updates/tool
(
cd $mc/dt/updates/tool/
ln -s ../../folder1 v1
ln -s ../../folder2 v2
)

ls -la $mc/dt/updates/tool/

cp -r $mc/dt/folder1/ $ap7/dt/
cp -r $mc/dt/folder2/ $ap7/dt/
mkdir -p $ap8/dt/updates/tool/v1
mkdir -p $ap8/dt/updates/tool/v2
cp $mc/dt/folder1/* $ap8/dt/updates/tool/v1/
cp $mc/dt/folder2/* $ap8/dt/updates/tool/v2/


$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /updates/tool/v1/ | grep file1.1.dat


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

mcsub=$mc/sub

$mcsub/gen_env MIRRORCACHE_ROOT="'$mc/dt:testhost.com:testhost.vpn'" \
               MIRRORCACHE_SUBTREE=/updates \
               MIRRORCACHE_TOP_FOLDERS=tool \
               MIRRORCACHE_VPN_PREFIX='"11. 10.10"' \
               MIRRORCACHE_ROOT_COUNTRY=us

$mcsub/start

$mc/curl -Is /download/updates/tool/v1/file1.1.dat.mirrorlist
$mc/curl -Is --interface 127.0.0.15 /download/updates/tool/v2/file1.1.dat.mirrorlist

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mcsub/curl /tool/v1/file1.1.dat.metalink   | grep -C10 $($ap7/print_address)/folder1/file1.1.dat | grep -C10 $($ap8/print_address)/updates/tool/v1/file1.1.dat | grep testhost.com/folder1/file1.1.dat
$mcsub/curl /tool/v2/file1.1.dat.metalink   | grep -C10 $($ap8/print_address)/updates/tool/v2/file1.1.dat | grep testhost.com/folder2/file1.1.dat

$mcsub/curl /tool/v1/file1.1.dat.mirrorlist | grep -C30 $($ap7/print_address)/folder1/file1.1.dat | grep -C30 $($ap8/print_address)/updates/tool/v1/file1.1.dat | grep testhost.com/folder1/file1.1.dat
$mcsub/curl /tool/v2/file1.1.dat.mirrorlist | grep -C30 $($ap8/print_address)/updates/tool/v2/file1.1.dat | grep testhost.com/folder2/file1.1.dat

$mcsub/curl /tool/v1/file1.1.dat.metalink?IP=10.11.10.1  | grep testhost
$mcsub/curl /tool/v1/file1.1.dat.metalink?IP=10.11.10.1  | grep testhost.com
$mcsub/curl /tool/v1/file1.1.dat.metalink?IP=10.10.10.1  | grep testhost
rc=0
$mcsub/curl /tool/v1/file1.1.dat.metalink?IP=10.10.10.1  | grep testhost.com || rc=$?
test $rc -gt 0

# test request from ROOT_COUNTRY is just served
$mc/curl -i /download/folder1/file1.1.dat?COUNTRY=us | grep '200 OK'

echo success
