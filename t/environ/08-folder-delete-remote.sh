#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_TRUST_ADDR='127.0.0.1 127.0.0.3' $mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove folder1/file1.1.dt from ap8
rm $ap8/dt/folder1/file2.1.dat

$mc/curl -I /download/folder1/file2.1.dat
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/shoot

$mc/db/sql "select * from file"
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl --interface 127.0.0.2 -X DELETE -I /admin/folder_diff/1

# check nothing was actually deleted
test 2 == $($mc/db/sql "select count(*) from folder_diff")

$mc/curl --interface 127.0.0.2 -X DELETE -I -H 'x-forwarded-for: 127.0.0.1' /admin/folder_diff/1
$mc/curl --interface 127.0.0.2 -X DELETE -I -H 'x-forwarded-for: 127.0.0.1' /admin/folder_diff/1

test 2 == $($mc/db/sql "select count(*) from folder_diff")

# with 127.0.0.3 it actually works
$mc/curl --interface 127.0.0.3 -X DELETE -I /admin/folder_diff/1
test 0 == $($mc/db/sql "select count(*) from folder_diff")
