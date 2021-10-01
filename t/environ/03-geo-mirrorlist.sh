#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

for x in $mc $ap6 $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
done

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','cu','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','mx','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap9/print_address)','','t','ca','na'"

$mc/curl /download/folder1/file1.1.dat.mirrorlist

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/curl /download/folder1/file1.1.dat.mirrorlist?COUNTRY=mx | grep http
$mc/curl /download/folder1/file1.1.dat.mirrorlist?COUNTRY=ca | grep http | grep '(MX)'
