#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

# should deploy db
$mc/backstage/shoot

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','','t','de','eu'"

$mc/backstage/job -e mirror_location -a '["1"]'
$mc/backstage/shoot

res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 1')
[[ $res =~ 37.75.*-97.82 ]]
res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 2')
[[ ! $res =~ 37.75.*-97.82 ]]
