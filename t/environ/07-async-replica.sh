#!lib/test-in-container-environ.sh
set -ex

test "$MIRRORCACHE_DB_PROVIDER" != mariadb || {
    echo NOT IMPLEMENTED for MariaDB yet
    exit 0
}

mc=$(environ mc $(pwd))

pg=$(environ pg)

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3
$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
    MIRRORCACHE_DBREPLICA=$pg/dt MIRRORCACHE_DB=mc_test

# deploy DB
$mc/backstage/shoot

$pg/replicate $mc/db

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


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/start
$mc/backstage/job mirror_scan_schedule
$mc/backstage/start

$mc/curl -I /download/folder1/file1.1.dat

sleep $((MIRRORCACHE_SCHEDULE_RETRY_INTERVAL+1))
$mc/db/sql "select * from minion_jobs order by id"

$mc/curl -I /download/folder1/file1.1.dat | grep 302 \
   || ( sleep 1 ; $mc/curl -I /download/folder1/file1.1.dat | grep 302 ) \
   || ( sleep 5 ; $mc/curl -I /download/folder1/file1.1.dat | grep 302 ) \
   || ( sleep 5 ; $mc/curl -I /download/folder1/file1.1.dat | grep 302 ) \
   || ( sleep 5 ; $mc/curl -I /download/folder1/file1.1.dat | grep 302 ) \
   || ( sleep 5 ; $mc/curl -I /download/folder1/file1.1.dat | grep 302 )

$mc/db/sql "select count(*) from minion_jobs where task='folder_sync'"

# check the main server log doesn't have the main select query
rc=0
grep -Fq '( 6371 * acos( cos( radians' $mc/db/dt/log/*.log || rc=$?
test $rc -gt 0 || (
    echo 'FAIL: The query must present only in the replica log'
    exit 1
)

# check replica log has the main select query
grep -Fq '( 6371 * acos( cos( radians' $pg/dt/log/*.log || (
    echo 'FAIL: Cannot find query in the replica log'
    exit 1
)

echo PASS
