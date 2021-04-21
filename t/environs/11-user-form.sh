#!lib/test-in-container-environs.sh
set -ex

# Ensure that route for user management page requests authentication
# Ensure that routes for user management are protected

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9
mc9*/start.sh

pg9*/sql.sh -c "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli','eli@test','Eli Test','eli',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'" mc_test

mc9*/curl.sh admin/user -I | grep -E '302|/login'

mc9*/curl.sh admin/user/1 -I | grep -E '404|Not Found'

mc9*/curl.sh admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=admin'
test 0 == $(pg9*/sql.sh -t -c "select count(*) from acc where is_admin=1 and is_operator=1" mc_test)

mc9*/curl.sh admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=operator'
test 0 == $(pg9*/sql.sh -t -c "select count(*) from acc where is_admin=0 and is_operator=1" mc_test)
