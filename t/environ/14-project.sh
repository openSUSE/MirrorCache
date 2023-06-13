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
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path,etalon) select 'proj1','/project1', 3"
$mc/sql "insert into project(name,path,etalon) select 'proj 2','/project2', 3"

$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/shoot


$mc/curl /rest/project/proj1
$mc/curl /rest/project/proj1/mirror_summary
$mc/curl /rest/project/proj1/mirror_summary | grep -E '"current":"?4' | grep -E '"outdated":"?0'

$mc/backstage/job -e folder_sync -a '["/project1/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder2"]'
$mc/backstage/shoot

$mc/backstage/job -e folder_sync -a '["/project2/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder1"]'
$mc/backstage/shoot

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

rc=0
$mc/curl /rest/repmirror  | grep -F '"country":"jp","proj1score":"0","proj1victim":"","proj2score":"100","proj2victim":"","region":"as","url":"'$($ap4/print_address)'"' || rc=$?
echo proj1 is not on ap4, so it shouldnt appear in repmirror at all
test $rc -gt 0

$mc/curl /rest/repmirror  | grep -F '{"country":"cn","proj1score":"50","proj1victim":"","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1284"},{"country":"jp","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1274"},{"country":"de","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"eu","url":"127.0.0.1:1314"},{"country":"us","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1294"},{"country":"us","proj1score":"50","proj1victim":"\/project1\/folder2","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1304"}'

$mc/curl /rest/project | grep -F '{"alias":"proj2","name":"proj 2","path":"\/project2"}' | grep -F '{"alias":"proj1","name":"proj1","path":"\/project1"}'

echo ceck the same when DB is offline
$mc/db/stop
$mc/curl /rest/repmirror  | grep -F '{"country":"cn","proj1score":"50","proj1victim":"","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1284"},{"country":"jp","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1274"},{"country":"de","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"eu","url":"127.0.0.1:1314"},{"country":"us","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1294"},{"country":"us","proj1score":"50","proj1victim":"\/project1\/folder2","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1304"}'

$mc/curl /rest/project | grep -F '{"alias":"proj2","name":"proj 2","path":"\/project2"}' | grep -F '{"alias":"proj1","name":"proj1","path":"\/project1"}'

echo now restart the service while DB is offline
$mc/stop
ENVIRON_MC_DB_AUTOSTART=0 $mc/start

$mc/curl /rest/repmirror  | grep -F '{"country":"cn","proj1score":"50","proj1victim":"","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1284"},{"country":"jp","proj2score":"100","proj2victim":"","region":"as","url":"127.0.0.1:1274"},{"country":"de","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"eu","url":"127.0.0.1:1314"},{"country":"us","proj1score":"100","proj1victim":"","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1294"},{"country":"us","proj1score":"50","proj1victim":"\/project1\/folder2","proj2score":"100","proj2victim":"","region":"na","url":"127.0.0.1:1304"}'

$mc/curl /rest/project | grep -F '{"alias":"proj2","name":"proj 2","path":"\/project2"}' | grep -F '{"alias":"proj1","name":"proj1","path":"\/project1"}'

$mc/db/start

$mc/curl /rest/project/proj1/mirror_summary
$mc/curl /rest/project/proj1/mirror_summary | grep -E '"current":"?2' | grep -E '"outdated":"?2'

$mc/curl /rest/project/proj1/mirror_list | grep -E '{"current":"?1"?,"server_id":"?1"?,"url":"127.0.0.1:1294"},{"current":"?1"?,"server_id":"?3"?,"url":"127.0.0.1:1314"},{"current":"?0"?,"server_id":"?4"?,"url":"127.0.0.1:1284"},{"current":"?0"?,"server_id":"?2"?,"url":"127.0.0.1:1304"}'

echo request from jp should be redirected to ap4
$mc/curl -I /download/project2/folder1/file1.1.dat?COUNTRY=jp | grep $($ap4/print_address)

echo now disable proj 2 on ap4 - redirect should change
$mc/sql 'insert into server_project(server_id, project_id, state) select 5, 2, 0';
echo request from jp shouldnt be redirected to ap4 anymore, because we have disabled /project2 on it
rc=0
$mc/curl -I /download/project2/folder1/file1.1.dat?COUNTRY=jp | grep $($ap4/print_address) || rc=$?
test $rc -gt 0

echo success
