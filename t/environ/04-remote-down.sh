#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=http://$($ap9/print_address)

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}/repodata
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/{folder1,folder2,folder3}/repodata/repomd.xml   | xargs -n 1 touch
    touch $x/dt/folder3/Packages.gz
    $x/start
done

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','',1,'us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','',1,'us','na'"

# remove folder1/file1.1.dt from ap8
rm $ap8/dt/folder1/file2.1.dat

# first request redirected to root
$mc/curl -I /download/folder1/repodata/repomd.xml | grep $($ap9/print_address)
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap9/print_address)

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# mv $ap7/dt/folder1/file2.1.dat $ap8/dt/folder1/
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap7/print_address)
echo repomd is still taken from the root
$mc/curl -I /download/folder1/repodata/repomd.xml | grep $($ap9/print_address)

# shutdown root
$ap9/stop

if $ap9/status >& /dev/null ; then
    fail Root apache must be down
fi

echo mc properly redirects when root is down
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap7/print_address)

$ap9/start
$ap9/status
# since root is up again, redirect to root
$mc/curl -I /download/folder3/repodata/repomd.xml | grep $($ap9/print_address)

###########################
# check that repomd.xml in folder3 doesn't trigger folder sync
$mc/curl -I /download/folder3/repodata/repomd.xml | grep $($ap9/print_address)
$mc/curl -I /download/folder3/Packages.gz | grep $($ap9/print_address)
$mc/sql_test 0 == "select count(*) from folder where path ='/folder3'"

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/sql_test 0 == "select count(*) from folder where path ='/folder3'"
###########################

echo success
