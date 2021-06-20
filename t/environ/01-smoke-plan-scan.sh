#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=3
$mc/gen_env MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses'" \
        MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1 \
        MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=$MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.dat


$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','de','eu'"

$mc/curl -I /download/folder1/file1.dat?COUNTRY=mx
$mc/backstage/shoot
test 1 == $($mc/db/sql "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'")

$mc/db/sql "select * from minion_locks"

# request from mx goes to us
$mc/curl -Is /download/folder1/file1.dat?COUNTRY=mx | grep -C10 302 | grep "$($ap7/print_address)"
$mc/backstage/shoot
$mc/db/sql "select * from minion_locks"
# MIRRORCACHE_MIRROR_RESCAN_TIMEOUT hasn't passed yet, so no scanning job should occur
test 1 == $($mc/db/sql "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'")

sleep $MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT
sleep $MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT

$mc/curl -I /download/folder1/file1.dat?COUNTRY=mx | grep -C10 302 | grep "$($ap7/print_address)"
$mc/backstage/shoot
# now another job should start
test 2 == $($mc/db/sql "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'")
