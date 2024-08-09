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
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project1/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project2/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
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
$mc/sql "insert into server(hostname,urldir,enabled,country,region,sponsor) select '$($ap8/print_address)','','t','de','eu','Poznań'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path) select 'proj1','/project1'"
$mc/sql "insert into project(name,path) select 'proj 2','/project2'"

$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/shoot


$mc/curl /rest/project/1

$mc/backstage/job -e folder_sync -a '["/project1/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder2"]'
$mc/backstage/shoot

$mc/backstage/job -e folder_sync -a '["/project2/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder1"]'
$mc/backstage/shoot

$mc/backstage/job mirror_probe_projects
$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

rc=0
$mc/curl /rest/repmirror  | grep -F '"country":"jp","proj1score":"0","proj2score":"100","region":"as","url":"'$($ap4/print_address)'"' || rc=$?
echo proj1 is not on ap4, so it shouldnt appear in repmirror at all
test $rc -gt 0

$mc/curl /rest/repmirror  | grep -F '{"country":"cn","hostname":"127.0.0.1:1284"' | grep -oF '"sponsor":"Poznań"'

$mc/curl /rest/project | grep -F '"id":2,"name":"proj 2","path":"\/project2"' | grep -F '"id":1,"name":"proj1","path":"\/project1"'

echo check the same when DB is offline
$mc/db/stop
$mc/curl /rest/repmirror  | grep -F '{"country":"cn","hostname":"127.0.0.1:1284","proj1score":' | grep -oF '"sponsor":"Poznań"'

echo now restart the service while DB is offline
$mc/stop
ENVIRON_MC_DB_AUTOSTART=0 $mc/start

$mc/curl /rest/repmirror  | grep -F '{"country":"cn","hostname":"127.0.0.1:1284","proj1score":' | grep -oF '"sponsor":"Poznań"'

$mc/db/start

echo request from jp should be redirected to ap4
$mc/curl -I /download/project2/folder1/file1.1.dat?COUNTRY=jp | grep $($ap4/print_address)

echo now disable proj 2 on ap4 - redirect should change
$mc/sql 'update server_project set state = 0 where server_id = 5 and project_id = 2';
echo request from jp shouldnt be redirected to ap4 anymore, because we have disabled /project2 on it
rc=0
$mc/curl -I /download/project2/folder1/file1.1.dat?COUNTRY=jp | grep $($ap4/print_address) || rc=$?
test $rc -gt 0

echo success
