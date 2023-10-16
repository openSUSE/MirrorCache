#!lib/test-in-container-environ.sh
set -ex

mcmirror=$(environ mc5 $(pwd))
mcna=$(environ mc1 $(pwd))
mcnaeast=$(environ mc2 $(pwd))

ap8=$(environ ap8)
ap7=$(environ ap7)

$mcmirror/start

$mcmirror/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mcmirror/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mcmirror/sql "insert into server_capability_declaration(server_id, capability, enabled, extra) select '1','region','t','na-east,na-west'"

$mcmirror/curl /rest/server_location?region=na      | grep $($ap7/print_address) | grep $($ap8/print_address)
$mcmirror/curl /rest/server_location?region=na-east | grep $($ap7/print_address)
rc=0
$mcmirror/curl /rest/server_location?region=na-east | grep $($ap8/print_address) || rc=$?
test $rc -gt 0

$mcna/gen_env MIRRORCACHE_MIRROR_PROVIDER=$($mcmirror/print_address)/rest/server_location?region=na MIRRORCACHE_MIRROR_PROVIDER_SYNC_RETRY_INTERVAL=1
$mcna/start
# the job importing mirrors should schedule automatically because mirror_provider_region is defined
$mcna/backstage/shoot

$mcna/sql_test 2 = 'select count(*) from server' # both servers are imported
$mcna/curl /rest/server | grep $($ap7/print_address) | grep $($ap8/print_address) | grep '\bus\b'


$mcnaeast/gen_env MIRRORCACHE_INI=$mcnaeast/conf.ini

(
echo mirror_provider=$($mcmirror/print_address)/rest/server_location?region=na-east
echo
echo [db]
echo
) >> $mcnaeast/conf.ini


$mcnaeast/start
# the job importing mirrors should schedule automatically because mirror_provider_region is defined
$mcnaeast/backstage/shoot

$mcnaeast/sql_test 1 = 'select count(*) from server' # only one servers are imported

rc=0
$mcnaeast/curl /rest/server | grep $($ap7/print_address) | grep '"country":"us"'
$mcnaeast/curl /rest/server | grep $($ap8/print_address) || rc=$?

test $rc -gt 0

sleep 1
echo change server on mcmirror, make sure in gets synced
$mcmirror/sql "update server set country = 'ca' where id = 1";
$mcna/sql_test us = "select country from server where id = 1"
$mcna/backstage/shoot
$mcna/sql_test ca = "select country from server where id = 1"

echo now restart job on mc1, manually check that job is ok
sleep 1
$mcna/backstage/shoot

echo success
