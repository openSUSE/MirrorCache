#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_STAT_PARTITION=1

$mc/start
$mc/status

for x in $mc; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$mc/curl -Is /download/folder1/file1.1.dat

$mc/sql_test 0 == "select count(*) from stat"
month=$(date +%m)
$mc/sql_test 1 == "select count(*) from stat_$month"

