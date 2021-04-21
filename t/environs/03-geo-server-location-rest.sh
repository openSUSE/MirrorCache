#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
./environ.sh mc9 $(pwd)/MirrorCache
pg9*/start.sh
pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

MIRRORCACHE_TEST_TRUST_AUTH=1 mc9*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us',''" mc_test

mc9*/curl.sh rest/server/location/1 -X PUT
mc9*/backstage/shoot.sh

res=$(pg9*/sql.sh -t -c 'select round(lat,2), round(lng,2) from server' mc_test)
test ' 37.75 | -97.82' == "$res"

# let's restart server without MIRRORCACHE_TEST_TRUST_AUTH
mc9*/stop.sh
if mc9*/status.sh >/dev/null 2>&1; then
    echo MirrorCache must have been stopped here
    exit 1
fi

pg9*/sql.sh -c "update server set lat = 0, lng = 0 where id = 1" mc_test
mc9*/start.sh
mc9*/curl.sh rest/server/location/1 -X PUT
mc9*/backstage/shoot.sh
# should remain unchanged
res=$(pg9*/sql.sh -t -c 'select round(lat,2), round(lng,2) from server' mc_test)
test '  0.00 |  0.00' == "$res"

