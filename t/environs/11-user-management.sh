#!lib/test-in-container-environs.sh
set -ex

# Ensure that routes for user management work

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

# start MirrorCache with no authentication for all routes under /admin 
MIRRORCACHE_TEST_TRUST_AUTH=1 mc9*/start.sh

pg9*/sql.sh -c "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli','eli@test','Eli Test','eli',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'" mc_test
pg9*/sql.sh -t -c "select * from acc" mc_test

mc9*/curl.sh admin/user -I | grep '200'

mc9*/curl.sh admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=admin'
test 1 == $(pg9*/sql.sh -t -c "select count(*) from acc where is_admin=1 and is_operator=1" mc_test)

mc9*/curl.sh admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=operator'
test 1 == $(pg9*/sql.sh -t -c "select count(*) from acc where is_admin=0 and is_operator=1" mc_test)

mc9*/curl.sh admin/user/1 -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw 'role=user'
test 1 == $(pg9*/sql.sh -t -c "select count(*) from acc where is_admin=0 and is_operator=0" mc_test)

mc9*/curl.sh admin/user/1 -X DELETE >/dev/null
mc9*/curl.sh admin/user/1 -X DELETE | grep -E 'error|Not found'
test 0 == $(pg9*/sql.sh -t -c "select count(*) from acc" mc_test)
