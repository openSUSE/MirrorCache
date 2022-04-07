#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start

ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)

for x in $mc $ap7 $ap8 $ap6; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/project1/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project1/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap6/start
$ap7/start
$ap8/start

# remove a file from ap7
rm $ap7/dt/project1/folder2/file2.1.dat

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','',1,'us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','',1,'us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','',1,'us','na'"

$mc/sql "insert into project(name,path,etalon) select 'proj1','/project1', 1"

$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1","us"]'
$mc/backstage/shoot


$mc/curl -s /rest/project/proj1
$mc/curl -s /rest/project/proj1/mirror_summary
$mc/curl -s /rest/project/proj1/mirror_summary | grep -E '"current":"?3' | grep -E '"outdated":"?0'


$mc/backstage/job -e folder_sync -a '["/project1/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder2","us"]'
$mc/backstage/shoot
$mc/curl -s /rest/project/proj1/mirror_summary
$mc/curl -s /rest/project/proj1/mirror_summary | grep -E '"current":"?2' | grep -E '"outdated":"?1'

$mc/curl -s /rest/project/proj1/mirror_list
# $mc/curl -s /rest/project/proj1/mirror_list | grep -E '{"current":"?1"?,"server_id":"?1"?,"url":"127.0.0.1:1294"},{"current":"?1"?,"server_id":"?3"?,"url":"127.0.0.1:1314"},{"current":"?0"?,"server_id":"?2"?,"url":"127.0.0.1:1304"}'
$mc/curl -s /rest/project/proj1/mirror_list | grep '{"current":1,"server_id":1,"url":"127.0.0.1:1294"},{"current":1,"server_id":3,"url":"127.0.0.1:1314"},{"current":0,"server_id":2,"url":"127.0.0.1:1304"}'
