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

$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$na_address','na',''"
$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$eu_address','eu',''"
$mc9/db/sql "insert into subsidiary(hostname,region,uri) select '$as_address','as',''"

$mc9/start

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address) MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'"
$mc6/start
$mc7/gen_env MIRRORCACHE_REGION=eu MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address) MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'"
$mc7/start
$mc8/gen_env MIRRORCACHE_REGION=as MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_HEADQUARTER=$($mc9/print_address) MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'"
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
    echo 13         > mc$i/dt/folder1/file4.1.dat.zsync
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
    test  $(mc$i/sql "select md5 from hash where file_id=3") == $(mc$i/sql 'select md5 from hash where file_id=1')
done


echo Step 3. Add media symlinks and make sure they are imported properly
for i in 9 6 7 8; do
    ( cd mc$i/dt/folder1/ && ln -s file4.1.dat file-Media.iso )
    ( cd mc$i/dt/folder1/ && ln -s file4.1.dat xcurr.dat )
    ( cd mc$i/dt/folder1/ && ln -s file4.1.dat.zsync xcurr.dat.zsync )
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
    mc$i/sql_test file4.1.dat == "select hash.target from hash join file on id = file_id where name='file-Media.iso'"
    for x in '' metalink mirrorlist; do
        ext=""
        par=""
        [ -z "$x"] || ext=.$x
        [ -z "$x"] || par=?$x
        mc$i/curl -I /folder1/file-Media.iso$ext | grep -C 10 302 | grep /folder1/file4.1.dat$par | grep -v /download/folder1/file4.1.dat
    done
done

mc9/curl -IL /download/folder1/file-Media.iso | grep '200 OK'

echo Step 4. Add files, but hash calculation on the main server happens later
DELAY=1;

for i in 6 7 8 9; do
    echo 1111111113 > mc$i/dt/folder1/file1.2.dat
    echo 1111111113 > mc$i/dt/folder1/file4.2.dat
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/shoot
    MIRRORCACHE_HASHES_IMPORT_RETRY_DELAY=$DELAY mc$i/backstage/shoot -q hashes
    if test $i != 9; then
        test -z $(mc$i/sql "select md5 from hash where file_id=8")
        test -z $(mc$i/sql "select md5 from hash where file_id=9")
    else
        test $(mc$i/sql "select md5 from hash where file_id=8") == $(mc$i/sql 'select md5 from hash where file_id=9')
        test $(mc$i/sql "select md5 from hash where file_id=3") != $(mc$i/sql 'select md5 from hash where file_id=8')
    fi
done

sleep $DELAY

mc9/curl -I /download/folder1/file-Media.iso            | grep 'Location: /download/folder1/file4.1.dat'
mc9/curl -I /download/folder1/file-Media.iso.metalink   | grep 'Location: /download/folder1/file4.1.dat?metalink=1'
mc9/curl -I /download/folder1/file-Media.iso.mirrorlist | grep 'Location: /download/folder1/file4.1.dat?mirrorlist=1'

mc9/curl -I /download/folder1/xcurr.dat            | grep "Location: http://$na_address/download/folder1/xcurr.dat"
mc9/curl -I /download/folder1/xcurr.dat.metalink   | grep "Location: http://$na_address/download/folder1/xcurr.dat.metalink"
mc9/curl -I /download/folder1/xcurr.dat?meta4      | grep "Location: http://$na_address/download/folder1/xcurr.dat.meta4"
mc9/curl -I /download/folder1/xcurr.dat.mirrorlist | grep '200 OK'

mc9/curl -I /download/folder1/xcurr.dat.zsync.mirrorlist | grep '200 OK'

mc6/curl -IL /download/folder1/xcurr.dat            | grep "200 OK"
mc6/curl -IL /download/folder1/xcurr.dat.metalink   | grep "200 OK"
mc6/curl -IL /download/folder1/xcurr.dat?meta4      | grep "200 OK"
mc6/curl -IL /download/folder1/xcurr.dat.mirrorlist | grep '200 OK'



# now the hashes on subsidiaries should be retried and match the headquarter
for i in 6 7 8; do
    mc$i/backstage/shoot -q hashes
    test $(mc$i/sql "select md5 from hash where file_id=8") == $(mc9/sql 'select md5 from hash where file_id=9')
    test $(mc$i/sql "select md5 from hash where file_id=3") != $(mc9/sql 'select md5 from hash where file_id=9')
done

echo success
