#!lib/test-in-container-environ.sh
set -ex

mc1=$(environ mc1 $(pwd))
mc2=$(environ mc2 $(pwd))

ap9=$(environ ap9)

FAKEURL="notexists${RANDOM}.com"

$mc1/gen_env \
    MIRRORCACHE_REDIRECT=$FAKEURL

$mc2/gen_env \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_ROOT_NFS=$mc2/dt

rm -r $mc2/db
ln -s $mc1/db $mc2/

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9 $mc1 $mc2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

for x in $ap7 $ap8 $ap9; do
    $x/start
done

$mc1/start
$mc1/status

$mc2/start
$mc2/status

$mc1/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

# remove one of folders from NFS, imitating mount issue
rm -r $mc2/dt/folder2

echo first time REDIRECT is used
$mc1/curl -I /download/folder1/file1.1.dat | grep -C30 '302 Found' | grep $FAKEURL

echo first time REDIRECT is used even if folder is missing from NFS
$mc1/curl -I /download/folder2/file1.1.dat | grep -C30 '302 Found' | grep $FAKEURL

$mc2/backstage/job -e folder_sync_schedule_from_misses
# $mc/backstage/shoot
$mc2/backstage/job -e folder_sync_schedule
# $mc/backstage/shoot
$mc2/backstage/job -e mirror_scan_schedule
$mc2/backstage/shoot

$mc1/sql_test 2 == "select count(*) from minion_jobs where task = 'folder_sync'"
$mc1/sql_test 2 == "select count(*) from folder"

$mc1/curl -I /download/folder1/file1.1.dat | grep -C30 '302 Found' | grep $($ap7/print_address)

echo Now the scan happened despite the folder is missing in ROOT_NFS
$mc1/curl -I /download/folder2/file1.1.dat | grep -C30 '302 Found' | grep $($ap7/print_address)

echo success
