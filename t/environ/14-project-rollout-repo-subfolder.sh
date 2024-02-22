#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start

ap5=$(environ ap5)
ap4=$(environ ap4)

for x in $mc $ap5 $ap4; do
    mkdir -p $x/dt/project1/oss/repodata
    mkdir -p $x/dt/project1/non-oss/repodata
    touch $x/dt/project1/oss/repodata/0001-primary.xml.gz
    touch $x/dt/project1/non-oss/repodata/0001-primary.xml.gz
done

$ap4/start
$ap5/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path) select 'proj1 repo','/project1'"

$mc/backstage/job -e folder_sync -a '["/project1/oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/oss/repodata"]'
$mc/backstage/shoot

$mc/sql_test 1 == 'select count(*) from rollout'
$mc/sql_test 100 -lt 'select version from rollout'
$mc/sql_test 0001-primary.xml.gz == 'select filename from rollout'

$mc/sql_test 2 == 'select count(*) from rollout_server'

$mc/backstage/job -e folder_sync -a '["/project1/non-oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/non-oss/repodata"]'
$mc/backstage/shoot

$mc/sql_test 2 == 'select count(*) from rollout'
$mc/sql_test 100 -lt 'select version from rollout where project_id = 1 limit 1'

for x in $mc $ap5; do
    rm $x/dt/project1/non-oss/repodata/0001-primary.xml.gz
    touch $x/dt/project1/non-oss/repodata/0002-primary.xml.gz
done

$mc/backstage/job -e folder_sync -a '["/project1/oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/oss/repodata"]'
$mc/backstage/job -e folder_sync -a '["/project1/non-oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/non-oss/repodata"]'
$mc/backstage/shoot


$mc/sql_test 3 == 'select count(*) from rollout'
$mc/sql_test 1 == 'select count(*) from rollout_server where rollout_id = 3'

for x in $mc $ap4; do
    rm $x/dt/project1/oss/repodata/0001-primary.xml.gz
    touch $x/dt/project1/oss/repodata/0002-primary.xml.gz
done


rm $ap4/dt/project1/non-oss/repodata/0001-primary.xml.gz
touch $ap4/dt/project1/non-oss/repodata/0002-primary.xml.gz


$mc/backstage/job -e folder_sync -a '["/project1/oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/oss/repodata"]'
$mc/backstage/job -e folder_sync -a '["/project1/non-oss/repodata"]'
$mc/backstage/job -e mirror_scan -a '["/project1/non-oss/repodata"]'
$mc/backstage/shoot

$mc/sql_test 4 == 'select count(*) from rollout'
$mc/sql_test 1 == 'select count(*) from rollout_server where rollout_id = 4'
$mc/sql_test 2 == 'select count(*) from rollout_server where rollout_id = 3'

echo success
