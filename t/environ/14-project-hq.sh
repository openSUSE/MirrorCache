#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary (same DB as hq)
# 8 - ASIA subsidiary

# hq mirrors: ap1 ap2
# na mirrors: ap3 ap4
# eu mirrors: ap5 ap6
# as mirrors: ap7 ap8

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{project1,project2}/{folder1,folder2,folder3}
    echo $x/dt/{project1,project2}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    eval mc$i=$x
done

for i in 1 2 3 4 5 6 7 8; do
    x=$(environ ap$i)
    mkdir -p $x/dt/{project1,project2}/{folder1,folder2,folder3}
    echo $x/dt/{project1,project2}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
    eval ap$i=$x
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/sql "insert into subsidiary(hostname,region,local) select '$eu_address','eu','t'"
$mc9/sql "insert into subsidiary(hostname,region) select '$as_address','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','','t','br','sa'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','','t','br','sa'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','de','eu'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','dk','eu'"

$mc9/start

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address
$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','t','us','na'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','ca','na'"

$mc7/gen_env MIRRORCACHE_REGION=eu MIRRORCACHE_HEADQUARTER=$hq_address
rm -r $mc7/db
ln -s $mc9/db $mc7/db
$mc7/start

$mc8/gen_env MIRRORCACHE_REGION=as MIRRORCACHE_HEADQUARTER=$hq_address
$mc8/start
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','jp','as'"
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','jp','as'"

for i in 6 8 9; do
    mc$i/sql "insert into project(name,path,etalon) select 'proj1','/project1', 1"
    mc$i/sql "insert into project(name,path,etalon) select 'proj 2','/project2', 1"
    mc$i/backstage/job -e folder_sync -a '["/project1/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/project1/folder1"]'
    mc$i/backstage/job -e folder_sync -a '["/project1/folder2"]'
    mc$i/backstage/job -e mirror_scan -a '["/project1/folder2"]'
    mc$i/backstage/job -e folder_sync -a '["/project2/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/project2/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/job -e report -a '["once"]'
    mc$i/backstage/shoot
done

# all countries present in report
mc9/curl -s /rest/repmirror \
          | grep '"country":"br"' \
          | grep '"country":"de"' \
          | grep '"country":"dk"' \
          | grep '"country":"ca"' \
          | grep '"country":"us"' \
          | grep '"country":"jp"'

