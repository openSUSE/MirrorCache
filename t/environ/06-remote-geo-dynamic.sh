#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

$mc/gen_env MIRRORCACHE_ROOT=http://$($ap6/print_address) \
    MIRRORCACHE_STAT_FLUSH_COUNT=1 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3

for x in $ap6 $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start
done
$mc/start
$mc/status

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap9/print_address)','','t','cn','as'"

$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.dat

test 0 == "$(grep -c Poll $mc/.cerr)"

sleep 10
job_id=$($mc/backstage/job -e mirror_scan -a '["/folder1","cn"]')

# check redirects to headquarter are logged properly
$mc/db/sql "select * from stat"
test -1 == $($mc/db/sql "select mirror_id from stat where country='us'")
test -1 == $($mc/db/sql "select distinct mirror_id from stat where country='de'")
test -z $($mc/db/sql "select mirror_id from stat where country='cn'")

$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.dat | grep $($ap7/print_address)
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.dat | grep $($ap8/print_address)
$mc/curl --interface 127.0.0.3 /download/folder1/ | grep file1.dat

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

$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.dat
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.dat | grep $($ap9/print_address)

$mc/db/sql "select * from stat"
# check stats are logged properly
test 2 == $($mc/db/sql "select distinct mirror_id from stat where country='de' and mirror_id > 0")
test 1 == $($mc/db/sql "select count(*) from stat where country='de' and mirror_id > 0")

test 3 == $($mc/db/sql "select distinct mirror_id from stat where country='cn' and mirror_id > 0")
test 2 == $($mc/db/sql "select count(*) from stat where country='cn' and mirror_id > 0")

test 1 == $($mc/db/sql "select distinct mirror_id from stat where country='us' and mirror_id > 0")
test 1 == $($mc/db/sql "select count(*) from stat where country='us' and mirror_id > 0")

test 0 == "$(grep -c Poll $mc/.cerr)"

$mc/curl /rest/stat
$mc/curl /rest/stat | grep '"hit":4' | grep '"miss":2'

# now test stat_agg job by injecting some values into yesterday
$mc/backstage/stop
$mc/db/sql "insert into stat(path, dt, mirror_id, secure, ipv4, metalink, head) select '/ttt', now() - interval '1 day', mirror_id, 'f', 'f', 'f', 't' from stat"
$mc/db/sql "delete from minion_locks where name like 'stat_agg_schedule%'"
$mc/backstage/job stat_agg_schedule
$mc/backstage/shoot

$mc/db/sql "select * from stat_agg"
test 4 == $($mc/db/sql "select count(*) from stat_agg where period = 'day'")

$mc/curl /rest/stat
$mc/curl /rest/stat | grep '"hit":4' | grep '"miss":2' | grep '"prev_hit":4' | grep '"prev_miss":2'

test 0 == $($mc/db/sql "select sum(case when head then 0 else 1 end) from stat")
$mc/curl --interface 127.0.0.2 -i /download/folder1/file1.dat
test 1 == $($mc/db/sql "select sum(case when head then 0 else 1 end) from stat")

test 0 == $($mc/db/sql "select sum(case when metalink then 1 else 0 end) from stat")
$mc/curl --interface 127.0.0.2 -Is -H 'Accept: */*, application/metalink+xml' /download/folder1/file1.dat
test 1 == $($mc/db/sql "select sum(case when metalink then 1 else 0 end) from stat")
