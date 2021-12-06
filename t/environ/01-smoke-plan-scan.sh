#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))


MIRRORCACHE_RESCAN_INTERVAL=0

$mc/gen_env MIRRORCACHE_RESCAN_INTERVAL=$MIRRORCACHE_RESCAN_INTERVAL

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat


$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','de','eu'"

$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=mx
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

test 1 == $($mc/db/sql "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%'")

$mc/db/sql "select * from minion_locks"

$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=mx | grep -C10 302 | grep "$($ap7/print_address)"
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
# now another job should start
test 2 == $($mc/db/sql "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%'")

#######################################
$mc/curl --interface 127.0.0.3 -I /download/folder2/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder3/file1.1.dat.mirrorlist
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl --interface 127.0.0.3 /download/folder2/file1.1.dat.mirrorlist | grep $($ap8/print_address)
$mc/curl --interface 127.0.0.3 /download/folder2/file1.1.dat.mirrorlist | grep $($ap7/print_address)

$mc/curl --interface 127.0.0.3 /download/folder3/file1.1.dat.mirrorlist | grep $($ap8/print_address)
$mc/curl --interface 127.0.0.3 /download/folder3/file1.1.dat.mirrorlist | grep $($ap7/print_address)
#######################################

#######################################
# a folder is deleted from one of mirrors
# do rescan and make sure the mirror gone from mirrorlist
rm -r $ap8/dt/folder2
$mc/curl /download/folder2/file1.1.dat.mirrorlist | grep $($ap8/print_address)
$mc/backstage/job -e mirror_scan -a '["/folder2"]'
$mc/backstage/shoot
res=0
$mc/curl /download/folder2/file1.1.dat.mirrorlist | grep $($ap8/print_address) || res=$?
test $res -gt 0
#######################################
echo success
