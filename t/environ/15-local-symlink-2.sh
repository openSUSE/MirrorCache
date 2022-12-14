#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_BACKSTAGE_WORKERS=15 \
            MIRRORCACHE_RECKLESS=0

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

mkdir -p $mc/dt/{folder1,folder2}
echo 1  > $mc/dt/folder1/file1.1.dat
cp $mc/dt/folder{1,2}/file1.1.dat

mkdir -p $mc/dt/updates/tool
(
cd $mc/dt/updates/tool/
ln -s ../../folder1 latest
)

ls -la $mc/dt/updates/tool/

cp -r $mc/dt/folder1/ $ap7/dt/
mkdir -p $ap8/dt/updates/tool/latest
cp $mc/dt/folder1/* $ap8/dt/updates/tool/latest/

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /updates/tool/latest/ | grep file1.1.dat

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -Is /download/folder1/file1.1.dat.meta4

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -I /download/updates/tool/latest/file1.1.dat | grep '302 Found'
$mc/curl /download/updates/tool/latest/file1.1.dat.meta4 | grep $($ap7/print_address)/folder1/file1.1.dat

sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL 1
$mc/backstage/shoot

$mc/curl /download/updates/tool/latest/file1.1.dat.meta4 | grep -C10 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/latest/file1.1.dat

(
cd $mc/dt/updates/tool/
rm latest
ln -s ../../folder2 latest
echo 111 > latest/file2.1.dat
)
cp -r $mc/dt/folder2/ $ap7/dt/

echo at this point server doesnt know content of the folder anymore
$mc/curl -I /download/updates/tool/latest/file1.1.dat | grep '200 OK'

$mc/curl -I /download/updates/tool/latest/file2.1.dat | grep '200 OK'

sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL 1

$mc/backstage/shoot
$mc/curl /download/updates/tool/latest/file1.1.dat.meta4 | grep -C10 $($ap7/print_address)/folder2/file1.1.dat | grep $($ap8/print_address)/updates/tool/latest/file1.1.dat

$mc/curl -I /download/updates/tool/latest/file2.1.dat | grep '302 Found'
$mc/curl /download/updates/tool/latest/file2.1.dat.meta4 | grep  $($ap7/print_address)/folder2/file2.1.dat

echo success
