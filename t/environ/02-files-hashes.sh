#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
            MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_HASHES_COLLECT=1 \
            MIRRORCACHE_HASHES_PIECES_MIN_SIZE=5

$mc/start
$mc/status

for x in $mc; do
    mkdir -p $x/dt/folder1
    echo 1111111111 > $x/dt/folder1/file1.1.dat
done

# force scan
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot
$mc/backstage/shoot -q hashes

$mc/db/sql "select * from file"
$mc/db/sql "select * from hash"
test b2c5860a03d2c4f1f049a3b2409b39a8 == $($mc/db/sql 'select md5 from hash where file_id=1')
test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $($mc/db/sql 'select sha1 from hash where file_id=1')
test 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458 == $($mc/db/sql 'select sha256 from hash where file_id=1')
test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $($mc/db/sql 'select pieces from hash where file_id=1')


$mc/curl /download/folder1/file1.1.dat.metalink | grep -o "<size>$(stat --printf="%s" $mc/dt/folder1/file1.1.dat)</size>"
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o "<mtime>$(date +%s -r $mc/dt/folder1/file1.1.dat)</mtime>"
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash type="md5">b2c5860a03d2c4f1f049a3b2409b39a8</hash>'
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash type="sha-256">63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458</hash>'
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash>5179db3d4263c9cb4ecf0edbc653ca460e3678b7</hash>'
