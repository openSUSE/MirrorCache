#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)

$mc/gen_env MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_STAT_FLUSH_COUNT=1 \
    MIRRORCACHE_ROOT_COUNTRY=de \
    MIRRORCACHE_ROOT_LONGITUDE=11.07

$mc/start

for x in $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start
done

rm $ap8/dt/folder2/file2.dat

CZ_ADDRESS=$($ap8/print_address)
DE_ADDRESS=$($ap9/print_address)


$mc/db/sql "insert into server(hostname,urldir,enabled,country,region,lat,lng) select '$CZ_ADDRESS','','t','cz','eu',50.07,14.43"

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -I /download/folder1/file1.dat?COUNTRY=cz | grep $CZ_ADDRESS
$mc/curl -I /download/folder1/file1.dat?COUNTRY=de | grep $DE_ADDRESS

# use --interface to get latitude from the test geoip database
# 127.0.0.2 is US, so must be closer to de
$mc/curl --interface 127.0.0.2 -I '/download/folder1/file1.dat?REGION=eu' | grep $DE_ADDRESS
# 127.0.0.4 is CN, so must be closer to cz
$mc/curl --interface 127.0.0.4 -I '/download/folder1/file1.dat?REGION=eu' | grep $CZ_ADDRESS

# check order of the same in metalink file
$mc/curl --interface 127.0.0.2 '/download/folder1/file1.dat.metalink?REGION=eu' | grep -A1 $DE_ADDRESS | grep $CZ_ADDRESS
$mc/curl --interface 127.0.0.4 '/download/folder1/file1.dat.metalink?REGION=eu' | grep -A1 $CZ_ADDRESS | grep $DE_ADDRESS

#########################################
echo test scan is scheduled when metadata is missing
$mc/curl -Is --interface 127.0.0.3 '/download/folder2/file1.dat.metalink?COUNTRY=de' | grep -A1 $DE_ADDRESS
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
# $mc/backstage/job mirror_scan_schedule_from_misses
$mc/backstage/shoot
$mc/curl -is --interface 127.0.0.3 '/download/folder2/file1.dat.metalink?COUNTRY=de' | grep -A2 $DE_ADDRESS | grep $CZ_ADDRESS
$mc/sql 'select * from stat order by id desc limit 1'
$mc/sql_test 0 -le 'select mirror_id from stat order by id desc limit 1'
$mc/curl -is --interface 127.0.0.3 '/download/folder2/file1.dat.metalink?COUNTRY=cz' | grep -A2 $CZ_ADDRESS | grep $DE_ADDRESS
$mc/sql 'select * from stat order by id desc limit 1'
$mc/sql_test 0 -le 'select mirror_id from stat order by id desc limit 1'
$mc/curl -is --interface 127.0.0.3 '/download/folder2/file1.dat.mirrorlist?COUNTRY=cz' | grep $CZ_ADDRESS
$mc/sql 'select * from stat order by id desc limit 1'
$mc/sql_test 0 -le 'select mirror_id from stat order by id desc limit 1'
#########################################


# folder2/file2.dat is missing from the mirror in CZ, so it shouldnt be neither in metalink nor in mirrorlist
rc=0
$mc/curl -is --interface 127.0.0.3 '/download/folder2/file2.dat.metalink?COUNTRY=cz' | grep $CZ_ADDRESS || rc=$?
test $rc -gt 0
$mc/sql 'select * from stat order by id desc limit 1'
# but stat still should show hit
$mc/sql_test 0 -le 'select mirror_id from stat order by id desc limit 1'

# the same check for mirrorlist
rc=0
$mc/curl -is --interface 127.0.0.3 '/download/folder2/file2.dat.mirrorlist?COUNTRY=cz' | grep $CZ_ADDRESS || rc=$?
test $rc -gt 0
$mc/sql 'select * from stat order by id desc limit 1'
$mc/sql_test 0 -le 'select mirror_id from stat order by id desc limit 1'
#########################################
