#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_TRUST_ADDR=127.0.0.1 $mc/start
$mc/status

for x in $mc; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/{folder1,folder2,folder3}/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/{folder1,folder2,folder3}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$mc/curl -X POST -i /rest/sync_tree | grep 400

$mc/sql_test 0 == "select count(*) from folder"

$mc/curl -X POST -i /rest/sync_tree?path=/folder1 | grep '200 OK'
$mc/backstage/shoot

$mc/sql_test 4 == "select count(*) from folder"
$mc/sql_test 4 == "select count(*) from folder where sync_requested is not null"

