#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/start
$mc/status

ap7=$(environ ap7)

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

for x in $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/{folder1,folder2,folder3}/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/{folder1,folder2,folder3}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch

    # this is for recursive scan with crossreference
    ln -s $x/dt/folder3 $x/dt/folder2/folderX
    ln -s $x/dt/folder2 $x/dt/folder3/folderX
    $x/start
done

$mc/backstage/job -e folder_tree -a '["/folder1"]'
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/sql "select * from file"

$mc/curl -I /download/folder1/file2.1.dat | grep $($ap7/print_address)
$mc/curl -I /download/folder1/folder1/file1.1.dat | grep $($ap7/print_address)
$mc/curl -I /download/folder1/folder3/file2.1.dat | grep $($ap7/print_address)


$mc/backstage/job -e folder_tree -a '["/folder2"]'
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -I /download/folder2/file2.1.dat | grep $($ap7/print_address)
$mc/curl -I /download/folder2/folder1/file1.1.dat | grep $($ap7/print_address)
$mc/curl -I /download/folder2/folder3/file2.1.dat | grep $($ap7/print_address)
