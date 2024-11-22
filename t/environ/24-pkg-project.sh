#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

files=(
    /folder1/x86_64/mypkg-1.1-1.1.x86_64.rpm
    /folder2/x86_64/yourpkg-1.1-1.1.x86_64.rpm
    )


for f in ${files[@]}; do
    for x in $mc $ap7 $ap8; do
        mkdir -p $x/dt${f%/*}
        echo 1111111111 > $x/dt$f
    done
done

$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/sql "insert into project(name,path,prio) select 'proj','/folder2', 100"

for f in ${files[@]}; do
    $mc/curl -Is /download$f
done

$mc/backstage/job -e folder_sync -a '["/folder1/x86_64"]'
$mc/backstage/job -e folder_sync -a '["/folder2/x86_64"]'
$mc/backstage/shoot

$mc/curl /rest/search/packages?official=1 | grep yourpkg

rc=0
$mc/curl /rest/search/packages?official=1 | grep mypkg || rc=1
test $rc -gt 0

echo success
