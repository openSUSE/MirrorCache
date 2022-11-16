#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

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
mkdir -p $ap8/dt/updates/tool/v1
cp $mc/dt/folder1/* $ap8/dt/updates/tool/v1/


$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /updates/tool/v1/ | grep file1.1.dat


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -Is /download/updates/tool/v1/file1.1.dat.mirrorlist


$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl /download/updates/tool/v1/ | grep file1.1.dat

# make sure db doesn't have info about symlinked folder
$mc/sql_test 0 == "select count(*) from file where folder_id = (select id from folder where path = '/updates/tool/v1')"
# even if we scanned symlinked folder, the real folder is in db
$mc/sql_test 2 == "select count(*) from file where folder_id = (select id from folder where path = '/folder1')"

# thest that both folders exist
$mc/sql_test 2 == "select count(*) from file where folder_id in (select id from folder where path in ('/updates/tool/v1', '/folder1'))"

$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=us | grep $($ap7/print_address)/folder1/file1.1.dat
$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=de | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat

$mc/curl /download/updates/tool/v1/file1.1.dat.mirrorlist | grep -C 20 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat
$mc/curl /download/updates/tool/v1/file1.1.dat.metalink   | grep -C 10 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat

