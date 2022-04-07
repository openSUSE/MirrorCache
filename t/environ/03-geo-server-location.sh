#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

# should deploy db
$mc/backstage/shoot

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/',1,'us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','/',1,'de','eu'"

$mc/backstage/job -e mirror_location -a '["1"]'
$mc/backstage/shoot

res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 1')
test '37.75	-97.82' == "$res"
res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 2')
test '37.75	-97.82' != "$res"
