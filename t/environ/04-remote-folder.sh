#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap=$(environ ap)

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($ap/print_address) \
    MIRRORCACHE_TRUST_ADDR=127.0.0.1 \
    MIRRORCACHE_RENDER_DIR_REMOTE_PROMISE_TIMEOUT=1

mkdir -p $ap/dt/{folder1,folder2,folder3}
touch $ap/dt/folder1/file1.1.dat

$ap/start

$mc/start
$mc/status

$mc/curl /download/folder1/ | grep 'Waiting in queue'
$mc/backstage/shoot
$mc/curl /download/folder1/ | grep file1.1.dat

cnt=$($mc/sql 'select count(*) from minion_jobs')

$mc/curl -X POST /rest/sync?path=/folder1

$mc/sql_test $cnt -lt 'select count(*) from minion_jobs'

echo success
