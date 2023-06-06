#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap6=$(environ ap6)
ap5=$(environ ap5)
ap4=$(environ ap4)
ap3=$(environ ap3)

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($ap3/print_address) \
    MIRRORCACHE_REDIRECT=$($ap4/print_address) \
    MIRRORCACHE_OFFLINE_REDIRECT="'$($ap6/print_address) $(ap5/print_address)'"

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap3 $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat

$ap3/start
$ap3/curl /folder1/ | grep file1.1.dat


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -I /download/folder1/file1.1.dat | grep '302'

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/stop
$mc/curl -I /download/folder1/file1.1.dat          | grep -E "$($ap6/print_address)|$($ap5/print_address)"/folder1/file1.1.dat
$mc/curl /download/folder1/file1.1.dat.metalink | grep -C 10 "http://$($ap6/print_address)/folder1/file1.1.dat<" | grep "$($ap5/print_address)"
$mc/curl /download/folder1/file1.1.dat.meta4    | grep -C 10 "http://$($ap6/print_address)/folder1/file1.1.dat<" | grep "$($ap5/print_address)"

$mc/db/start

$mc/curl -H "Accept: */*, application/metalink+xml" -s /download/folder1/file2.1.dat | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'
$mc/curl /download/folder1/file2.1.dat.metalink | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'

echo success
