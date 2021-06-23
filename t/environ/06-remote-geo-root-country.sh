#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

$mc/gen_env MIRRORCACHE_ROOT=http://$($ap6/print_address) \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
    MIRRORCACHE_STAT_FLUSH_COUNT=1 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3 \
    MIRRORCACHE_ROOT_COUNTRY=de

for x in $ap6 $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start
done
$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','cz','eu'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap9/print_address)','','t','cn','as'"

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -I /download/folder1/file1.dat?COUNTRY=de
$mc/curl -I /download/folder1/file1.dat?COUNTRY=it
$mc/curl -I /download/folder1/file1.dat?COUNTRY=cz
$mc/curl -I /download/folder1/file1.dat?COUNTRY=cn
$mc/curl -I /download/folder1/file1.dat?COUNTRY=au

$mc/db/sql "select * from stat order by id"
test 7 == $($mc/db/sql "select count(*) from stat")
test 0 == $($mc/db/sql "select count(*) from stat where country='us'")
test 1 == $($mc/db/sql "select count(*) from stat where mirror_id = -1") # only one miss
test 1 == $($mc/db/sql "select count(*) from stat where country='cz' and mirror_id = 2")
test 2 == $($mc/db/sql "select count(*) from stat where mirror_id = 0") # only de

$mc/backstage/job stat_agg_schedule
$mc/backstage/shoot

$mc/curl /rest/stat
$mc/curl /rest/stat | grep '"hit":6' | grep '"miss":1'
