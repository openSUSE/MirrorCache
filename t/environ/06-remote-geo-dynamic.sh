#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

$mc/gen_env MIRRORCACHE_ROOT=http://$($ap6/print_address) \
    MIRRORCACHE_STAT_FLUSH_COUNT=1 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1 \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

for x in $ap6 $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
done
$mc/start
$mc/status

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule_from_misses
$mc/backstage/job mirror_scan_schedule
$mc/backstage/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap9/print_address)','','t','cn','as'"

$mc/curl --interface 127.0.0.3 /download/folder1/ | grep file1.1.dat
$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat

test 0 == "$(grep -c Poll $mc/.cerr)"

sleep 10
job_id=$($mc/backstage/job -e mirror_scan -a '["/folder1"]')
sleep 3

# check redirects to headquarter are logged properly
$mc/db/sql "select * from stat"

$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat | grep $($ap7/print_address)
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep $($ap8/print_address)

sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
test t == $($mc/db/sql "select state in ('finished','failed') from minion_jobs where id=$job_id") || sleep 3
$mc/backstage/status
$mc/db/sql "select state from minion_jobs where id=$job_id"

$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat | grep $($ap9/print_address)

test 0 == "$(grep -c Poll $mc/.cerr)"

$mc/curl --interface 127.0.0.2 -i /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.2 -Is -H 'Accept: */*, application/metalink+xml' /download/folder1/file1.1.dat
