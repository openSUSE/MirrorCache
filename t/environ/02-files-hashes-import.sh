#!lib/test-in-container-environ.sh
set -ex

# mc environ by number:
# 9 - headquarter
# 6 - NA subsidiary

# hq mirros: ap1 ap2
# na mirros: ap3 ap4

for i in 6 9; do
    x=$(environ mc$i $(pwd))
    eval mc$i=$x
done

for i in 1 2 3 4; do
    x=$(environ ap$i)
    $x/start
    eval ap$i=$x
done

for x in mc9 ap1 ap2 ap3 ap4; do
    mkdir -p $x/dt/{folder1,folder2,folder3,folder4}
    echo $x/dt/{folder1,folder2,folder3,folder4}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo 1111111111 > $x/dt/folder1/file1.1.dat
    echo 1111111112 > $x/dt/folder2/file1.1.dat
    ( cd $x/dt ; ln -s folder1 link1 )
done


# set the same modification time for file1.1.dat
touch -d "$(date -R -r $mc9/dt/folder1/file1.1.dat)" {$ap1,$ap2,$ap3,$ap4}/dt/folder1/file1.1.dat

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2

# deploy db
$mc9/gen_env MIRRORCACHE_HASHES_COLLECT=1 MIRRORCACHE_HASHES_PIECES_MIN_SIZE=5 "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3 folder4 link1'" MIRRORCACHE_BRANDING=SUSE MIRRORCACHE_WORKERS=4 MIRRORCACHE_DAEMON=1
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','eu'"
$mc9/start
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','','t','jp','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','','t','jp','as'"

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3 link1'" MIRRORCACHE_HASHES_IMPORT=1 MIRRORCACHE_ROOT=http://$($mc9/print_address)
$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','t','de','eu'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','dk','eu'"

for i in 9 6; do
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/shoot -q hashes
done

curl -s "http://$hq_address/folder1/?hashes" | grep file1.1.dat
curl -s "http://$na_address/folder1/?hashes&since=2021-01-01" | grep file1.1.dat

for i in 9 6; do
    test b2c5860a03d2c4f1f049a3b2409b39a8 == $(mc$i/sql 'select md5 from hash where file_id=1')
    test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $(mc$i/sql 'select sha1 from hash where file_id=1')
    test 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458 == $(mc$i/sql 'select sha256 from hash where file_id=1')
    test 5179db3d4263c9cb4ecf0edbc653ca460e3678b7 == $(mc$i/sql 'select pieces from hash where file_id=1')
    test 2a276e680779492af2ed54ba5661ac5f35b39e363c95a55ddfac644c1aca2c3f68333225362e66536460999a7f86b1f2dc7e8ef469e3dc5042ad07d491f13de2 == $(mc$i/sql 'select sha512 from hash where file_id=1')
done

mc9/curl -sL /folder1/file1.1.dat.metalink | grep 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458
mc9/curl -s /folder1/file1.1.dat.metalink?COUNTRY=xx | grep 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458
mc9/curl -s /folder1/file1.1.dat.mirrorlist | grep 63d19a99ef7db94ddbb1e4a5083062226551cd8197312e3aa0aa7c369ac3e458

rc=0
echo /download shouldnt be shown when MIRRORCACHE_TOP_FOLDERS is set and MIRRORCACHE_BRANDING==SUSE
mc9/curl -s /folder1/file1.1.dat.mirrorlist | grep /download || rc=$?
test $rc -gt 0

echo Erase size in file and make sure it is taken from hash
mc9/sql 'update file set size=0, mtime=null'
mc9/curl -sL /folder1/file1.1.dat.metalink | grep -F -C10 '<size>11</size>'

echo Import folder unknown on master
curl -si "http://$hq_address/folder2?hashes"
mc9/backstage/shoot
mc9/backstage/shoot -q hashes
test d8f5889697e9ec5ba9a8ab4aede6e7d1d7858884e81db19b3e9780d6a64671a3 == $(mc9/sql 'select sha256 from hash where file_id=3')

mc6/backstage/job -e folder_sync -a '["/folder2"]'
mc6/backstage/shoot
mc6/backstage/shoot -q hashes

test d8f5889697e9ec5ba9a8ab4aede6e7d1d7858884e81db19b3e9780d6a64671a3 == $(mc6/sql 'select sha256 from hash where file_id=3')

DELAY=1;
echo Import folder unknown on master, but relay on automatic retry
mc6/backstage/job -e folder_sync -a '["/folder3"]'
mc6/backstage/shoot
MIRRORCACHE_HASHES_IMPORT_RETRY_DELAY=$DELAY mc6/backstage/shoot -q hashes

mc9/backstage/shoot
mc9/backstage/shoot -q hashes
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc9/sql 'select sha256 from hash where file_id=5')

sleep $DELAY
mc6/backstage/shoot -q hashes
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc6/sql 'select sha256 from hash where file_id=5')


test -n "$(mc6/sql 'select hash_last_import from folder where id=3')"


echo Emulate hashes on master were calculated only partially

mc9/backstage/job -e folder_sync -a '["/folder4"]'
mc9/backstage/shoot
mc9/backstage/shoot -q hashes
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc9/sql 'select sha256 from hash where file_id=7')
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc9/sql 'select sha256 from hash where file_id=8')

mc9/sql 'delete from hash where file_id=8'

mc6/backstage/job -e folder_sync -a '["/folder4"]'
mc6/backstage/shoot
MIRRORCACHE_HASHES_IMPORT_RETRY_DELAY=$DELAY mc6/backstage/shoot -q hashes

test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc9/sql 'select sha256 from hash where file_id=7')
test                                                                  -z "$(mc9/sql 'select sha256 from hash where file_id=8')"
echo Recalculate hashes on HQ
mc9/backstage/job -e folder_hashes_create -a '["/folder4"]'
mc9/backstage/shoot

sleep $DELAY
mc6/backstage/shoot -q hashes # this should retry the import because some hashes were missing
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc9/sql 'select sha256 from hash where file_id=7')
test e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 == $(mc6/sql 'select sha256 from hash where file_id=8')

test -n "$(mc6/sql 'select hash_last_import from folder where id=3')"


echo check how symlink work
cnt=$(mc6/sql 'select count(*) from file')

mc9/curl -I /link1/file1.1.dat
mc6/curl -I /link1/file1.1.dat

mc9/backstage/job folder_sync_schedule_from_misses
mc9/backstage/job folder_sync_schedule
mc9/backstage/job mirror_scan_schedule
mc9/backstage/shoot
mc9/backstage/shoot -q hashes

mc9/curl -I /link1/file1.1.dat | grep -E "$($ap1/print_address)|$($ap2/print_address)"

mc6/backstage/job folder_sync_schedule_from_misses
mc6/backstage/job folder_sync_schedule
mc6/backstage/job mirror_scan_schedule
mc6/backstage/shoot
mc6/backstage/shoot -q hashes

echo number of files shouldnt increase because we were rendering links

mc6/sql_test $cnt == 'select count(*) from file'
# mc6/sql_test /link1 == 'select pathfrom from redirect'

mc6/sql_test /link1 == "select path from folder where path = '/link1'"

mc6/sql_test 0 -lt "select count(*) from folder_diff join folder on folder_id = folder.id where path ='/link1'"

mc6/curl -I /link1/file1.1.dat | grep -E "$($ap4/print_address)|$($ap3/print_address)"

mc6/curl /link1/file1.1.dat.meta4 \
    | grep -C20 $($ap3/print_address)/link1/file1.1.dat \
    | grep -C20 $($ap3/print_address)/folder1/file1.1.dat \
    | grep -C20 $($ap4/print_address)/link1/file1.1.dat \
    | grep      $($ap4/print_address)/folder1/file1.1.dat

echo success
