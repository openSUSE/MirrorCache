#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
$mc/gen_env MIRRORCACHE_STAT_FLUSH_COUNT=1
$mc/start
$mc/status

ap7=$(environ ap7)

for x in $mc $ap7; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

$ap7/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"

$mc/curl -I /download/folder1/file1.dat

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

# check redirection works
$mc/curl -I /download/folder1/file1.dat | grep -C20 302 | grep $($ap7/print_address)

# now remove the file shut down ap7 and call mirror_check
rm $ap7/dt/folder1/file1.dat
$mc/backstage/job mirror_check_from_stat
$mc/backstage/shoot

# no download anymore
$mc/curl -I /download/folder1/file1.dat | grep -C20 '200 OK'
