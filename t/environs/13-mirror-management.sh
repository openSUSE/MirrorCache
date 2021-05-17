#!lib/test-in-container-environs.sh
set -ex

# Test audit logs creation for mirror actions

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

# Start MirrorCache with fake logged in admin user
MIRRORCACHE_TEST_TRUST_AUTH=1 mc9*/start.sh

mc9*/curl.sh 'app/server' -I | grep '200'

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test

# Add new mirror
# TODO: check why empty id needs to be given here and fix accepting empty urldir maybe? :)
mc9*/curl.sh 'rest/server' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=&urldir=&hostname=127.0.0.1:1314&country=eu&enabled=0'

# Update mirror urldir
mc9*/curl.sh 'rest/server/2' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=2&urldir=/somedir&hostname=127.0.0.1:1314&country=eu&enabled=0'

# Look for server_update event with both ids: who executed action and what was affected
mc9*/curl.sh 'admin/auditlog/ajax?search[value]=event:server_update' | grep 'server_update' | grep '"user_id":-2' | grep '\\\"id\\\":\\\"2\\\"'

# Delete mirror
mc9*/curl.sh 'rest/server/2' -X DELETE >/dev/null
mc9*/curl.sh 'rest/server/2' -X DELETE | grep 'error'

# Look for server_delete event with both ids: who executed action and what was affected
mc9*/curl.sh 'admin/auditlog/ajax?search[value]=event:server_delete' | grep 'server_delete' | grep '"user_id":-2' | grep '\\\"id\\\":2'

mc9*/curl.sh 'logout'

# Expect error when attempting to update/delete a mirror and no user is logged in (current_user is undef)
mc9*/curl.sh 'rest/server/2' -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=2&urldir=/somedir&hostname=127.0.0.1:1314&country=eu&enabled=0' | grep 'error'
mc9*/curl.sh 'rest/server/2' -X DELETE | grep 'error'
