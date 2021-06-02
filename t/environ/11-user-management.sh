#!lib/test-in-container-environ.sh
set -ex

# Ensure that routes for user management work

mc=$(environ mc $(pwd))

# Start MirrorCache with fake logged in admin user
MIRRORCACHE_TEST_TRUST_AUTH=1 $mc/start

$mc/db/sql "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli','eli@test','Eli Test','eli',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'"
$mc/db/sql "select * from acc"

$mc/curl /admin/user -I | grep '200'

$mc/curl /admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=admin'
test 1 == $($mc/db/sql "select count(*) from acc where is_admin=1 and is_operator=1")

# Look for user_update event with both ids: who executed action and who was affected
$mc/curl '/admin/auditlog/ajax?search\[value\]=event:user_update' | grep 'user_update' | grep '"user_id":-2' | grep '\\\"updated_user_id\\\":1'

$mc/curl /admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=operator'
test 1 == $($mc/db/sql "select count(*) from acc where is_admin=0 and is_operator=1")

$mc/curl /admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=user'
test 1 == $($mc/db/sql "select count(*) from acc where is_admin=0 and is_operator=0")

$mc/curl /admin/user/1 -X DELETE >/dev/null
$mc/curl /admin/user/1 -X DELETE | grep 'error'
test 0 == $($mc/db/sql "select count(*) from acc")

# Look for user_delete event with both ids: who executed action and who was affected
$mc/curl '/admin/auditlog/ajax?search\[value\]=event:user_delete' | grep 'user_delete' | grep '"user_id":-2' | grep '\\\"deleted_user_id\\\":1'

# Filter all 3 user_update events
$mc/curl '/admin/auditlog/ajax?search\[value\]=event:user_update' | grep 'user_update' | grep '"recordsFiltered":3'

# Filter one specific event by id
$mc/curl '/admin/auditlog/ajax?search\[value\]=id:2' | grep '"recordsFiltered":1'

$mc/db/sql "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli2','eli2@test','Eli2 Test','eli2',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'"
$mc/db/sql "select * from acc"

$mc/curl -X POST /logout

# Expect error when attempting to update/delete a user and no user is logged in (current_user is undef)
# (and /admin route is accesible due to starting MirrorCache with MIRRORCACHE_TEST_TRUST_AUTH environment variable set)
$mc/curl /admin/user/2 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=operator' | grep 'error'
$mc/curl /admin/user/2 -X DELETE | grep 'error'
