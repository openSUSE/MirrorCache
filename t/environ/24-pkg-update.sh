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
    /folder1/x86_64/yourpkg-1.1-1.1.x86_64.rpm
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


for f in ${files[@]}; do
    $mc/curl -Is /download$f
done

$mc/backstage/job -e folder_sync -a '["/folder1/x86_64"]'
$mc/backstage/shoot

$mc/sql_test 2 ==  "select count(*) from pkg"
$mc/sql_test 2 ==  "select count(*) from metapkg"

$mc/curl /rest/package/mypkg

$mc/curl /rest/search/packages?package=mypkg
$mc/curl "/rest/search/packages?package=mypkg&arch=x86_64"
$mc/curl "/rest/search/packages/?arch=x86_64&repo=folder1"


$mc/curl /rest/search/package_locations?package=my

$mc/curl "/rest/search/package_locations?package=mypkg&arch=x86_64"
$mc/curl "/rest/search/package_locations?package=mypkg&repo=folder1"
$mc/curl "/rest/search/package_locations?package=mypkg&repo=folder1&arch=x86_64"


rm $mc/dt/folder1/x86_64/yourpkg-1.1-1.1.x86_64.rpm
cp $mc/dt/folder1/x86_64/mypkg-{1,2}.1-1.1.x86_64.rpm
mkdir -p $mc/dt/folder2/x86_64
cp $mc/dt/folder{1,2}/x86_64/mypkg-2.1-1.1.x86_64.rpm
cp $mc/dt/folder2/x86_64/mypkg{,2}-2.1-1.1.x86_64.rpm

$mc/backstage/job -e folder_sync -a '["/folder1/x86_64"]'
$mc/backstage/job -e folder_sync -a '["/folder2/x86_64"]'
$mc/backstage/shoot

$mc/sql_test 3 ==  "select count(*) from pkg"
$mc/sql_test 3 ==  "select count(*) from metapkg"

$mc/curl /rest/search/packages?package=mypkg

$mc/curl '/rest/search/package_locations?package=mypkg&repo=folder2'

$mc/curl /rest/search/package_locations?package=yourpkg

echo success
