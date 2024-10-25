#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_HASHES_COLLECT=1 \
            MIRRORCACHE_ZSYNC_COLLECT=dat \
            MIRRORCACHE_HASHES_PIECES_MIN_SIZE=5

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/folder1
    echo 1111111111 > $x/dt/folder1/file1.1.dat
    echo 1111111111 > $x/dt/folder1/file2.1.dat
    ( cd $x/dt/folder1/ && ln -s file2.1.dat x-Media.dat )
done

$ap7/start
rm $ap7/dt/folder1/file2.1.dat # this mirror is missing the file for whatever reasons
rm $ap7/dt/folder1/x-Media.dat
touch $ap7/dt/folder1/x-Media.dat # but still has the symlink
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

# force scan
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -IL /download/folder1/x-Media.dat
rc=0
$mc/curl -IL /download/folder1/x-Media.dat | grep $($ap7/print_address) || rc=$?
test $rc -gt 0

$mc/curl -IL /download/folder1/x-Media.dat | grep $($ap8/print_address)

echo success
