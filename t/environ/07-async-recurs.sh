#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_BACKSTAGE_WORKERS=15 \
            MIRRORCACHE_RECKLESS=0
$mc/start
$mc/status

ap7=$(environ ap7)

for x in $mc $ap7; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/{folder1,folder2,folder3}/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/{folder1,folder2,folder3}/folder1/{file1.1,file2.1}.dat | xargs -n 1 touch

    # this is for recursive scan with crossreference
    ln -s $x/dt/folder3 $x/dt/folder2/folderX
    ln -s $x/dt/folder2 $x/dt/folder3/folderX
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

$mc/backstage/job -e folder_tree -a '["/folder1"]'
$mc/backstage/job -e folder_tree -a '["/folder2"]'
$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/start

sleep 1

$mc/curl -I /download/folder1/file1.1.dat | grep 302 \
   || ( sleep 1 && $mc/curl -I /download/folder1/file1.1.dat | grep 302 ) || ( sleep 10 && $mc/curl -I /download/folder1/file1.1.dat | grep 302 )

$mc/db/sql "select count(*) from minion_jobs where task='folder_sync'"


$mc/curl -I /download/folder2/file2.1.dat | grep $($ap7/print_address) || ( sleep 10 && $mc/curl -I /download/folder2/file2.1.dat | grep $($ap7/print_address) )
$mc/curl -I /download/folder2/folder1/file1.1.dat | grep $($ap7/print_address) || ( sleep 10 && $mc/curl -I /download/folder2/folder1/file1.1.dat | grep $($ap7/print_address) )
$mc/curl -I /download/folder2/folder1/file2.1.dat | grep $($ap7/print_address)
