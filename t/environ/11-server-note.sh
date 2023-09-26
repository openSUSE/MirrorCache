#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap8=$(environ ap8)
ap7=$(environ ap7)

$mc/backstage/shoot
$mc/sql "insert into acc(username,email,fullname,nickname,is_operator,is_admin,t_created,t_updated) select 'eli','eli@test','Eli Test','eli',0,0,'2021-01-14 11:19:25','2021-01-14 11:19:25'"

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/start
$mc/curl /rest/server/note/$($ap7/print_address) -I | grep -E '302|/login'

$mc/stop
MIRRORCACHE_TRUST_ADDR=127.0.0.1 $mc/start

$mc/curl /rest/server/note/$($ap7/print_address) -X POST -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' --data-raw "hostname=$($ap7/print_address)&kind=note&msg=test"

test test == $($mc/sql "select msg from server_note where hostname='$($ap7/print_address)'")

$mc/curl /rest/server/note/$($ap7/print_address) -i | grep 'test'

$mc/sql "insert into server_capability_check(server_id, capability, dt, extra) select 1, 'http', now(), 'unknown error'"

echo success
