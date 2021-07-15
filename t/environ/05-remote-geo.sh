#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

$mc/gen_env MIRRORCACHE_ROOT=http://$($ap6/print_address)

for x in $ap6 $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
done

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap9/print_address)','','t','cn','as'"

# we need to request file from two countries, so all mirrors will be scanned
$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat

# also requested file in folder2 from country where no mirrors present
$mc/curl -I /download/folder2/file1.1.dat?COUNTRY=dk

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat | grep $($ap9/print_address)
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep $($ap8/print_address)
$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat | grep $($ap7/print_address)

# since Denmark has no mirrors - german mirror have been scanned and now serves the request
$mc/curl -I /download/folder2/file1.1.dat?COUNTRY=dk | grep $($ap8/print_address)
