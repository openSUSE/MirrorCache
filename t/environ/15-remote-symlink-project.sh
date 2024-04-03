#!lib/test-in-container-environ.sh
set -ex

mc1=$(environ mc1 $(pwd))
mc2=$(environ mc2 $(pwd))

mc=$mc1

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

mkdir -p $mc/dt/folder1
echo 123456     > $mc/dt/folder1/file1.1.dat
echo 12         > $mc/dt/folder1/file2.1.dat
echo 1234567890 > $mc/dt/folder1/file3.1.dat
touch $mc/dt/folder1/content

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

$mc/backstage/start
mc=$mc2

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($mc1/print_address)/download \
    MIRRORCACHE_REDIRECT=$($ap7/print_address) \
    MIRRORCACHE_REDIRECT_HUGE=$($ap7/print_address) \
    MIRRORCACHE_SMALL_FILE_SIZE=5 \
    MIRRORCACHE_HUGE_FILE_SIZE=8


$mc/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/sql "insert into project(name,path) select 'updates','/updates'"
# restart to refresh info about projects
$mc/stop && $mc/start

$mc/curl -I /download/updates/tool/v1/file1.1.dat.mirrorlist

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

echo redirect is to symlinked folder
$mc/curl -I /download/updates/tool/v1/file1.1.dat
$mc/curl -I /download/updates/tool/v1/file1.1.dat | grep $($ap7/print_address)/folder1/file1.1.dat
echo redirect of small and huge files is also to symlinked folder
$mc/curl -I /download/updates/tool/v1/file2.1.dat | grep $($ap7/print_address)/folder1/file2.1.dat
$mc/curl -I /download/updates/tool/v1/file3.1.dat | grep $($ap7/print_address)/folder1/file3.1.dat
$mc/curl -I /download/updates/tool/v1/content     | grep $($ap7/print_address)/folder1/content

echo now tests the same with nfs

echo MIRRORCACHE_ROOT_NFS=$mc1/dt >> $mc/env.conf
$mc/stop && $mc/start
$mc/curl -I /download/updates/tool/v1/file1.1.dat | grep $($ap7/print_address)/folder1/file1.1.dat
echo redirect of small and huge files is also to symlinked folder
$mc/curl -I /download/updates/tool/v1/file2.1.dat | grep $($ap7/print_address)/folder1/file2.1.dat
$mc/curl -I /download/updates/tool/v1/file3.1.dat | grep $($ap7/print_address)/folder1/file3.1.dat
$mc/curl -I /download/updates/tool/v1/content     | grep $($ap7/print_address)/folder1/content

$mc/backstage/job mirror_scan_schedule
$mc/backstage/job mirror_probe_projects # fill server_project table
$mc/backstage/shoot

$mc/curl /download/updates/tool/v1/ | grep file1.1.dat

# make sure db doesn't have info about symlinked folder
$mc/sql_test 0 == "select count(*) from file where folder_id = (select id from folder where path = '/updates/tool/v1')"
# even if we scanned symlinked folder, the real folder is in db
$mc/sql_test 4 == "select count(*) from file where folder_id = (select id from folder where path = '/folder1')"

$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=us | grep $($ap7/print_address)/folder1/file1.1.dat
$mc/curl -I /download/updates/tool/v1/file1.1.dat?COUNTRY=de | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat

$mc/curl /download/updates/tool/v1/file1.1.dat.mirrorlist | grep -C 20 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat
$mc/curl /download/updates/tool/v1/file1.1.dat.metalink   | grep -C 10 $($ap7/print_address)/folder1/file1.1.dat | grep $($ap8/print_address)/updates/tool/v1/file1.1.dat


echo success
