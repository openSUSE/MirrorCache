#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap8=$(environ ap8)
ap7=$(environ ap7)


$mc/start
$mc/status

mkdir -p $mc/dt/folder1
echo 123456     > $mc/dt/folder1/file1.1.dat

mkdir -p $mc/dt/folder2
echo abcdef     > $mc/dt/folder2/file1.2.dat

mkdir -p $mc/dt/updates/tool
(
cd $mc/dt/updates/tool/
ln -s ../../folder1 v1
)

ls -la $mc/dt/updates/tool/

cp -r $mc/dt/folder*/ $ap7/dt/
mkdir -p $ap8/dt/updates/tool/v1
cp $mc/dt/folder1/* $ap8/dt/updates/tool/v1/


$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /updates/tool/v1/ | grep file1.1.dat


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -I /download/updates/tool/v1/file1.1.dat.mirrorlist

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/job -e folder_sync -a '["/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/folder2"]'
$mc/backstage/shoot

# normally it is created inside FolderSyncScheduleFromMisses
$mc/sql "insert into folder(path) select '/updates/tool/v1'"

$mc/backstage/job -e folder_sync -a '["/updates/tool/v1"]'
$mc/backstage/job -e mirror_scan -a '["/updates/tool/v1"]'
$mc/backstage/shoot

echo redirect is to symlinked folder
$mc/curl -I /download/updates/tool/v1/file1.1.dat | grep $($ap7/print_address)/folder1/file1.1.dat

$mc/curl /download/updates/tool/v1/ | grep file1.1.dat

# make sure db doesn't have info about symlinked folder
$mc/sql_test 0 == "select count(*) from file where folder_id = (select id from folder where path = '/updates/tool/v1')"
# even if we scanned symlinked folder, the real folder is in db
$mc/sql_test 1 == "select count(*) from file where folder_id = (select id from folder where path = '/folder1')"

$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=us | grep $($ap7/print_address)/folder1/file1.1.dat
$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=de | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat

$mc/curl /download/updates/tool/v1/file1.1.dat.mirrorlist | grep -C 20 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat
$mc/curl /download/updates/tool/v1/file1.1.dat.metalink   | grep -C 10 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat


echo now change destination of the symlink and scan it
(
cd $mc/dt/updates/tool/
rm v1
ln -s ../../folder2 v1
ls -la
)

$mc/curl -I /download/updates/tool/v1/file1.2.dat?COUNTRY=us
rc=0
$mc/curl -IL /download/updates/tool/v1/file1.2.dat?COUNTRY=de
$mc/curl -IL /download/updates/tool/v1/file1.2.dat?COUNTRY=de | grep '404 Not Found' || rc=$?

test $rc -gt 0

echo success
