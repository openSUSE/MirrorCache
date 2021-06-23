#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_TEST_TRUST_AUTH=1 $mc/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us','na'"

$mc/curl /rest/server/location/1 -X PUT
$mc/backstage/shoot

res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 1')
test ' 37.75 | -97.82' == "$res"

# let's restart server without MIRRORCACHE_TEST_TRUST_AUTH
$mc/stop
if $mc/status >/dev/null 2>&1; then
    echo MirrorCache must have been stopped here
    exit 1
fi

$mc/db/sql "update server set lat = 0, lng = 0 where id = 1"
$mc/start
# $mc/curl -X PUT /rest/server/location/1
$mc/curl /rest/server/location/1 -X PUT
$mc/backstage/shoot
# should remain unchanged
res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server')
test '  0.00 |  0.00' == "$res"

