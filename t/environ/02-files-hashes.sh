#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_HASHES_COLLECT=1 \
            MIRRORCACHE_ZSYNC_COLLECT=dat \
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

# this value 96ff97ccb1 is also reported by zsyncmake (the last bytes are hashes):
# hexdump -C file1.1.dat.zsync
# 00000000  7a 73 79 6e 63 3a 20 30  2e 36 2e 32 0a 46 69 6c  |zsync: 0.6.2.Fil|
# 00000010  65 6e 61 6d 65 3a 20 66  69 6c 65 31 2e 31 2e 64  |ename: file1.1.d|
# 00000020  61 74 0a 4d 54 69 6d 65  3a 20 4d 6f 6e 2c 20 31  |at.MTime: Mon, 1|
# 00000030  30 20 4a 61 6e 20 32 30  32 32 20 31 33 3a 32 38  |0 Jan 2022 13:28|
# 00000040  3a 32 33 20 2b 30 30 30  30 0a 42 6c 6f 63 6b 73  |:23 +0000.Blocks|
# 00000050  69 7a 65 3a 20 32 30 34  38 0a 4c 65 6e 67 74 68  |ize: 2048.Length|
# 00000060  3a 20 31 31 0a 48 61 73  68 2d 4c 65 6e 67 74 68  |: 11.Hash-Length|
# 00000070  73 3a 20 31 2c 32 2c 33  0a 55 52 4c 3a 20 6d 63  |s: 1,2,3.URL: mc|
# 00000080  31 2f 64 74 2f 66 6f 6c  64 65 72 31 2f 66 69 6c  |1/dt/folder1/fil|
# 00000090  65 31 2e 31 2e 64 61 74  0a 53 48 41 2d 31 3a 20  |e1.1.dat.SHA-1: |
# 000000a0  35 31 37 39 64 62 33 64  34 32 36 33 63 39 63 62  |5179db3d4263c9cb|
# 000000b0  34 65 63 66 30 65 64 62  63 36 35 33 63 61 34 36  |4ecf0edbc653ca46|
# 000000c0  30 65 33 36 37 38 62 37  0a 0a 96 ff 97 cc b1     |0e3678b7.......|

$mc/sql_test 96ff97ccb1 == "select encode(zhashes::bytea, 'hex') from hash where file_id=1"


$mc/curl /download/folder1/file1.1.dat.metalink | grep -o "<size>$(stat --printf="%s" $mc/dt/folder1/file1.1.dat)</size>"
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o "<mtime>$(date +%s -r $mc/dt/folder1/file1.1.dat)</mtime>"
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash type="md5">b2c5860a03d2c4f1f049a3b2409b39a8</hash>'
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash type="sha-256">63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458</hash>'
$mc/curl /download/folder1/file1.1.dat.metalink | grep -o '<hash>5179db3d4263c9cb4ecf0edbc653ca460e3678b7</hash>'
