#!lib/test-in-container-environ.sh
set -ex

# mc environ by number:
# 9 - headquarter
# 6 - NA subsidiary

# hq mirros: ap1 ap2
# na mirros: ap3 ap4

for i in 9 6; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    echo 1111111111 > $x/dt/folder1/file1.dat
    eval mc$i=$x
done

for i in 1 2 3 4; do
    x=$(environ ap$i)
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    echo 1111111111 > $x/dt/folder1/file1.dat
    eval ap$i=$x
    $x/start
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2

# deploy db
$mc9/gen_env MIRRORCACHE_HASHES_COLLECT=1 MIRRORCACHE_HASHES_PIECES_MIN_SIZE=5 "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/start
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','','t','jp','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','','t','jp','as'"

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','t','us','na'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','ca','na'"

for i in 9 6; do
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    [[ $i == 6 ]] && mc$i/backstage/job -e folder_hashes_import -a '["/folder1"]' || :
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
done

curl -s "http://$hq_address/folder1/?hashes" | grep file1.dat
curl -s "http://$na_address/folder1/?hashes&since=2021-01-01" | grep file1.dat

for i in 9 6; do
    test b2c5860a03d2c4f1f049a3b2409b39a8 == $(mc$i/db/sql 'select md5 from hash where file_id=1')
    test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $(mc$i/db/sql 'select sha1 from hash where file_id=1')
    test 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458 == $(mc$i/db/sql 'select sha256 from hash where file_id=1')
    test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $(mc$i/db/sql 'select pieces from hash where file_id=1')
done
