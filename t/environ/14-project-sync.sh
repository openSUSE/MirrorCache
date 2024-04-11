#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start

ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)
ap5=$(environ ap5)
ap4=$(environ ap4)

for x in $mc $ap7 $ap8 $ap6 $ap5 $ap4; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/project1/{folder1,folder2,folder3}
    mkdir -p $x/dt/project2/{folder1,folder2,folder3}
    mkdir -p $x/dt/project3/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project1/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project2/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project3/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap4/start
$ap5/start
$ap6/start
$ap7/start
$ap8/start

# remove a file from ap7
rm $ap7/dt/project1/folder2/file2.1.dat
rm -r $ap5/dt/project1/folder2/
rm -r $ap4/dt/project1/

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path,db_sync_every) select 'proj1','/project1', 1"
$mc/sql "insert into project(name,path,db_sync_every) select 'proj 2','/project2', 0"
$mc/sql "insert into project(name,path,db_sync_every,db_sync_last) select 'proj 3','/project3', 1, now() - interval '1 hour'"

$mc/backstage/job -e project_sync_schedule -a '["once"]'
$mc/backstage/shoot
$mc/backstage/job -e mirror_scan_schedule -a '["once"]'
$mc/backstage/shoot

$mc/curl -I /download/project1/folder1/file1.1.dat?COUNTRY=jp
$mc/curl -I /download/project1/folder1/file1.1.dat?COUNTRY=jp | grep '302 Found'

echo success
