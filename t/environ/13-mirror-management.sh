#!lib/test-in-container-environ.sh
set -ex

# Test audit logs creation for mirror actions

mc=$(environ mc $(pwd))

# Start MirrorCache with fake logged in admin user
MIRRORCACHE_TRUST_ADDR=127.0.0.1 $mc/start

$mc/curl /app/server -I | grep '200'

$mc/sql "insert into server(hostname,sponsor,sponsor_url,urldir,enabled,country,region) select '127.0.0.1:1304','openSUSE','opensuse.org','','t','us','na'"

# Add new mirror
# TODO: check why empty id needs to be given here
$mc/curl '/rest/server' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=&urldir=&hostname=127.0.0.1:1314&country=eu&enabled=0'

# Update mirror urldir and sponsor
$mc/curl '/rest/server/2' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=2&urldir=/somedir&sponsor=SUSE&hostname=127.0.0.1:1314&country=eu&enabled=0'

$mc/sql_test SUSE == 'select sponsor from server where id = 2'

# Look for server_update event with both ids: who executed action and what was affected
$mc/curl '/admin/auditlog/ajax?search\[value\]=event:server_update' | grep 'server_update' | grep '"user_id":-2' | grep '\\\"id\\\":\\\"2\\\"'

# Delete mirror
$mc/curl '/rest/server/2' -X DELETE >/dev/null
$mc/curl '/rest/server/2' -X DELETE | grep 'error'

# Look for server_delete event with both ids: who executed action and what was affected
$mc/curl '/admin/auditlog/ajax?search\[value\]=event:server_delete' | grep 'server_delete' | grep '"user_id":-2' | grep '\\\"id\\\":2'

$mc/curl -X POST /logout

# Expect error when attempting to update/delete a mirror and no user is logged in (current_user is undef)
$mc/curl '/rest/server/2' -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw 'id=2&urldir=/somedir&hostname=127.0.0.1:1314&country=eu&enabled=0' | grep 'error'
$mc/curl '/rest/server/2' -X DELETE | grep 'error'

echo success 13-mirror-management.sh
