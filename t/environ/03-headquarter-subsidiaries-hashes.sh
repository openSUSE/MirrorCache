#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary
# 8 - ASIA subsidiary

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo 1111111111 > $x/dt/folder1/file1.1.dat
    eval mc$i=$x
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'" MIRRORCACHE_HASHES_COLLECT=1
$mc9/backstage/shoot

$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$na_address','na','/download'"
$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$eu_address','eu','/download'"
$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$as_address','as','/download'"

$mc9/start

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address)
$mc6/start
$mc7/gen_env MIRRORCACHE_REGION=eu MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address)
$mc7/start
$mc8/gen_env MIRRORCACHE_REGION=as MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address)
$mc8/start


$mc9/curl -I /download/folder1/file1.1.dat.mirrorlist
$mc9/backstage/job folder_sync_schedule_from_misses
$mc9/backstage/job folder_sync_schedule
$mc9/backstage/shoot
$mc9/backstage/shoot -q hashes

$mc9/curl -I /download/folder1/file1.1.dat.mirrorlist
# these calls normally called by ajax in mirrorlist UI
$mc6/curl -I '/download/folder1/file1.1.dat?mirrorlist&json'
$mc7/curl -I '/download/folder1/file1.1.dat?mirrorlist&json'
$mc8/curl -I '/download/folder1/file1.1.dat?mirrorlist&json'

for i in 6 7 8 9; do
    mc$i/backstage/job folder_sync_schedule_from_misses
    mc$i/backstage/job folder_sync_schedule
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
    test b2c5860a03d2c4f1f049a3b2409b39a8 == $(mc$i/db/sql 'select md5 from hash where file_id=1')
done

echo Step 2. Add more files to folder1 and make sure only new hashes are transfered

for i in 9 6 7 8; do
    echo 1111111112 > mc$i/dt/folder1/file1.1.dat
    echo 1111111112 > mc$i/dt/folder1/file4.1.dat
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
    test  $(mc$i/db/sql "select md5 from hash where file_id=3") == $(mc$i/db/sql 'select md5 from hash where file_id=1')
done


