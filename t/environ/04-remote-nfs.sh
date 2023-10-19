#!lib/test-in-container-environ.sh
set -ex

# we need mc1 to emulate problem with nfs mount, so content of nfs is different from content of ROOT in mc2
mc1=$(environ mc1 $(pwd))
mc2=$(environ mc2 $(pwd))

ap9=$(environ ap9)

FAKEURL="notexists${RANDOM}.com"

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3

$mc2/gen_env \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
    MIRRORCACHE_REDIRECT=$FAKEURL \
    MIRRORCACHE_ROOT_NFS=$mc1/dt

rm -r $mc2/db
ln -s $mc1/db $mc2/

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9 $mc1 $mc2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo 111112 > $x/dt/folder1/file2.1-Media.iso
    echo 111113 > $x/dt/folder1/file2.1-Media.iso.zsync
    ( cd $x/dt/folder1 && ln -s file2.1-Media.iso.zsync file-Media.iso.zsync )

    mkdir -p $x/dt/updates/tool
    (
        cd $x/dt/updates/tool/
        ln -s ../../folder1 latest
    )
done

for x in $ap7 $ap8 $ap9; do
    $x/start
done

$mc1/start
$mc1/status

$mc2/start
$mc2/status

$mc2/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

# remove one of folders from NFS, imitating mount issue
rm -r $mc1/dt/folder2

echo first time REDIRECT is used
$mc2/curl -I /download/folder1/file1.1.dat | grep -C30 '302 Found' | grep $FAKEURL

echo first time REDIRECT is used even if folder is missing from NFS
$mc2/curl -I /download/folder2/file1.1.dat | grep -C30 '302 Found' | grep $FAKEURL

$mc2/backstage/job -e folder_sync_schedule_from_misses
$mc2/backstage/job -e folder_sync_schedule
$mc2/backstage/job -e mirror_scan_schedule
$mc2/backstage/shoot

$mc2/sql_test 2 == "select count(*) from minion_jobs where task = 'folder_sync'"
$mc2/sql_test 2 == "select count(*) from folder"

$mc2/curl -I /download/folder1/file1.1.dat | grep -C30 '302 Found' | grep $($ap7/print_address)

echo Now the scan happened despite the folder is missing in ROOT_NFS
$mc2/curl -I /download/folder2/file1.1.dat | grep -C30 '302 Found' | grep $($ap7/print_address)

$mc2/curl /download/updates/tool/latest/file1.1.dat.meta4 | grep $($ap7/print_address)/folder1/file1.1.dat

sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

$mc2/backstage/shoot

echo now we learned about all 3 folders
$mc2/sql_test 3 == 'select count(*) from folder'

$mc2/curl -H 'Accept: Application/x-zsync' -IL /download/folder1/file-Media.iso.zsync    | grep '404 Not Found'
$mc2/curl -H 'Accept: Application/x-zsync' -I  /download/folder1/file2.1-Media.iso.zsync | grep '404 Not Found' # we don't have zhashes for this file
$mc2/curl -H 'Accept: Application/x-zsync' -I  /download/folder1/file2.1-Media.iso | grep '404 Not Found' # we don't have zhashes for this file
$mc2/curl -H 'Accept: Application/metalink+xml' -I /download/folder1/file2.1-Media.iso | grep '200 OK'
$mc2/curl -H 'Accept: Application/metalink+xml, */*' -I /download/folder1/file2.1-Media.iso | grep '200 OK'
$mc2/curl -H 'Accept: Application/metalink+xml, */*' -I /download/folder1/file-Media.iso.zsync | grep --color=never -P '/download/folder1/file2.1-Media.iso.zsync\r$'

$mc2/curl -I /download/folder1/file-Media.iso.zsync | grep --color=never -P '/download/folder1/file2.1-Media.iso.zsync\r$'

echo success
