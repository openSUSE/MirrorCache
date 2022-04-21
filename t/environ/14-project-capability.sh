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

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/sql "insert into project(name,path,etalon) select 'proj1','/project1', 1"

$mc/sql "insert into server_project(server_id,project_id,state) select 3,1,-1"


$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/shoot

# covers both MariaDB and Pg implementations
$mc/sql "select notes from minion_jobs where task = 'mirror_scan'" | grep -C100 hash1 | grep hash2 || \
  $mc/sql "select note_key, note_value from minion_jobs join minion_notes on job_id = id where task = 'mirror_scan'" | grep -C100 hash1 | grep hash2

rc=0
$mc/sql "select notes from minion_jobs where task = 'mirror_scan'" | grep -q hash3 || rc=$?
test $rc -gt 0 || fail 'hash3 should not be in notes'


rm -r $ap7/dt/project1
$mc/backstage/job -e mirror_probe_projects
$mc/backstage/shoot
$mc/sql_test 0 == "select state from server_project where server_id = 2 and project_id = 1"
$mc/sql_test -1 == "select state from server_project where server_id = 3 and project_id = 1"


$mc/sql "update server_project set state = 0 where server_id = 3 and project_id = 1"
$mc/backstage/job -e mirror_probe_projects
$mc/backstage/shoot
$mc/sql_test 0 == "select state from server_project where server_id = 2 and project_id = 1"
$mc/sql_test 1 == "select state from server_project where server_id = 3 and project_id = 1"


echo success
