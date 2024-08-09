#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary
# 8 - ASIA subsidiary

SMALL_FILE_SIZE=3
HUGE_FILE_SIZE=9
FAKEURL1="notexists${RANDOM}.com"
FAKEURL2="notexists${RANDOM}.com"

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo -n 1234 > $x/dt/folder1/filebig1.1.dat
    echo -n 123  > $x/dt/folder1/filesmall1.1.dat
    echo -n 123456789 > $x/dt/folder1/filehuge1.1.dat
    echo '[]'    > $x/dt/folder1/file.json
    mkdir $x/dt/folder1/media.1
    echo 1 > $x/dt/folder1/media.1/media
    eval mc$i=$x
done

hq_address=$($mc9/print_address)
hq_interface=127.0.0.10
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3' \
             MIRRORCACHE_HUGE_FILE_SIZE=$HUGE_FILE_SIZE \
             MIRRORCACHE_REDIRECT=$FAKEURL1 \
             MIRRORCACHE_REDIRECT_HUGE=$FAKEURL2 \
             MIRRORCACHE_ROOT_NFS="$mc9/dt" \
             MIRRORCACHE_SMALL_FILE_SIZE=$SMALL_FILE_SIZE

$mc9/backstage/shoot

$mc9/db/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$as_address','as'"

$mc9/start
$mc6/start
$mc7/start
$mc8/start

echo the root folder is not redirected
curl --interface $eu_interface -Is http://$hq_address/ | grep '200 OK'
curl --interface $eu_interface -Is http://$hq_address/download/folder1/media.1/media | grep '200 OK'

mc9/curl -I -H 'Accept: */*, application/metalink+xml'                      /folder1/media.1/media | grep '200 OK'
mc9/curl -I -H 'Accept: */*, application/metalink+xml, application/x-zsync' /folder1/media.1/media | grep '200 OK'

echo check redirection from headquarter
curl --interface $na_interface -Is http://$hq_address/download/folder1/filebig1.1.dat | grep "Location: http://$na_address/download/folder1/filebig1.1.dat"
curl --interface $eu_interface -Is http://$hq_address/download/folder1/filebig1.1.dat | grep "Location: http://$eu_address/download/folder1/filebig1.1.dat"
curl --interface $as_interface -Is http://$hq_address/download/folder1/filebig1.1.dat | grep "Location: http://$as_address/download/folder1/filebig1.1.dat"

echo check redirection from na
curl --interface $na_interface -Is http://$na_address/download/folder1/filebig1.1.dat | grep '200 OK'
curl --interface $eu_interface -Is http://$na_address/download/folder1/filebig1.1.dat | grep '200 OK'

echo check redirection from eu
curl --interface $eu_interface -Is http://$eu_address/download/folder1/filebig1.1.dat | grep '200 OK'

echo check redirection from as
curl --interface $as_interface -Is http://$as_address/download/folder1/filebig1.1.dat | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/download/folder1/filebig1.1.dat?COUNTRY=cn | grep '200 OK'

echo check non-download routers shouldnt be redirected
curl --interface $na_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/rest/server | grep '200 OK'
curl --interface $na_interface -Is http://$na_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$eu_address/rest/server | grep '200 OK'

echo check small files are not redirected
curl --interface $na_interface -Is http://$hq_address/download/folder1/filebig1.1.dat | grep "Location: http://$na_address/download/folder1/filebig1.1.dat"
curl --interface $na_interface -Is http://$hq_address/download/folder1/filesmall1.1.dat | grep "200 OK"

echo check huge files are redirected to FAKEURL2
curl --interface $hq_interface -Is http://$hq_address/download/folder1/filehuge1.1.dat | grep "Location: http://$FAKEURL2/folder1/filehuge1.1.dat"

echo test cache-control
curl --interface $na_interface -Is http://$hq_address/download/folder1/filebig1.1.dat | grep -i 'cache-control'
curl --interface $na_interface -Is http://$hq_address/download/folder1/filehuge1.1.dat | grep -i 'cache-control'
rc=0
curl --interface $na_interface -Is http://$hq_address/download/folder1/filesmall1.1.dat | grep -i 'cache-control' || rc=$?
test $rc -gt 0

echo check content-type
ct=$($mc9/curl -I /download/folder1/file.json | grep Content-Type)
[[ "$ct" =~ application/json ]]
ct=$($mc9/curl -I /folder1/file.json | grep Content-Type)
[[ "$ct" =~ application/json ]]

echo check file listiing
$mc9/curl /download/folder1/ | grep file.json
$mc9/curl /folder1/ | grep file.json

echo /browse doesnt listen files - it will ajax them
rc=0
$mc9/curl /browse/folder1/ | grep file.json || rc=$?
test $rc -gt 0

echo for browsers default rendering of TOP_FOLDER should be /browse
rc=0
$mc9/curl -H 'User-Agent: Chromium/xyz' /folder1/ | grep file.json || rc=$?
test $rc -gt 0

echo unless /download is asked explicitly
$mc9/curl -H 'User-Agent: Chromium/xyz' /download/folder1/ | grep file.json

echo check metalink/mirrorlist for huge files reference FAKEURL2, but need to scan them first
$mc9/backstage/job -e folder_sync_schedule_from_misses
$mc9/backstage/job -e folder_sync_schedule
$mc9/backstage/shoot
curl --interface $hq_interface -s http://$hq_address/download/folder1/filehuge1.1.dat.metalink   | grep "http://$FAKEURL2/folder1/filehuge1.1.dat"
curl --interface $hq_interface -s http://$hq_address/download/folder1/filehuge1.1.dat.mirrorlist | grep "http://$FAKEURL2/folder1/filehuge1.1.dat"

echo success
