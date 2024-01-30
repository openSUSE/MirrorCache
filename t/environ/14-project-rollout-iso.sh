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
    mkdir -p $x/dt/project1/iso
    mkdir -p $x/dt/project2/iso
    echo $x/dt/project1/iso/proj1-Build1.1-Media.iso{,sha256} | xargs -n 1 touch
    echo $x/dt/project2/iso/proj1-Snapshot240131-Media.iso{,.sha256} | xargs -n 1 touch
done

$ap4/start
$ap5/start
$ap6/start
$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path,etalon) select 'proj1 ISO','/project1', 3"
$mc/sql "insert into project(name,path,etalon) select 'proj 2 ISO','/project2', 3"

$mc/backstage/job -e folder_sync -a '["/project1/iso"]'
$mc/backstage/job -e mirror_scan -a '["/project1/iso"]'
$mc/backstage/shoot

$mc/sql_test 1 == 'select count(*) from project_rollout'
$mc/sql_test 1.1 == 'select version from project_rollout'
$mc/sql_test proj1-Build1.1-Media.iso == 'select filename from project_rollout'

# $mc/sql_test 5 == 'select count(*) from project_rollout_server'

$mc/backstage/job -e folder_sync -a '["/project2/iso"]'
$mc/backstage/job -e mirror_scan -a '["/project2/iso"]'
$mc/backstage/shoot

$mc/sql_test 2 == 'select count(*) from project_rollout'
$mc/sql_test 240131 == 'select version from project_rollout where project_id = 2'

echo success
