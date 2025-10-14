#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

# pass too big value for prev_stat_id and make sure it is automatically adjusted
$mc/backstage/job -e exec -a '["ping google.com -c 3 & (sleep 1; pwd; errreerr; pwd)"]'
$mc/backstage/job -e exec -a '["mkdir tttttt"]'
$mc/backstage/job -e exec -a '["touch", "aaaaaa"]'
$mc/backstage-exec/shoot

$mc/backstage/job -e exec -a '["(sleep 1; pwd; errreerr; pwd) & ping -c 20 google.com"]'
$mc/backstage/job -e exec -a '[{"CMD": "(sleep 1; pwd; errreerr; pwd) & ping -c 20 google.com", "TIMEOUT": 6}]'
$mc/backstage-exec/shoot

# mc1/start
ls -lRa $mc | grep tttttt
ls -lRa $mc | grep aaaaaa

$mc/sql 'select * from minion_jobs'

$mc/sql_test 4 == "select count(*) from minion_jobs where state = 'finished'"
$mc/sql_test 1 == "select count(*) from minion_jobs where state = 'failed'"

echo success
