#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_TRUST_ADDR=127.0.0.1 $mc/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us','na'"

$mc/curl /rest/server/location/1 -X PUT
$mc/backstage/shoot

res=$($mc/db/sql 'select round(lat,2), round(lng,2) from server where id = 1')
[[ $res =~ '37.75' ]]
[[ $res =~ '-97.82' ]]

# let's restart server without MIRRORCACHE_TRUST_ADDR
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
[[ $res =~ 0.00.*0.00 ]]

