#!lib/test-in-container-environ.sh
set -ex

# Ensure that route for user management page requests authentication
# Ensure that routes for user management are protected

mc=$(environ mc $(pwd))
$mc/start
$mc/db/sql "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli','eli@test','Eli Test','eli',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'"

$mc/curl /admin/user -I | grep -E '302|/login'

$mc/curl /admin/user/1 -I | grep -E '404|Not Found'

$mc/curl /admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=admin'
test 0 == $($mc/db/sql "select count(*) from acc where is_admin=1 and is_operator=1")

$mc/curl /admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=operator'
test 0 == $($mc/db/sql "select count(*) from acc where is_admin=0 and is_operator=1")
