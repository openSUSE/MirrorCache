#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

rs=$(environ rs1)
$rs/configure_dir dt $rs/dt

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=rsync://$USER:$USER@$($rs/print_address)/dt \
    MIRRORCACHE_REDIRECT=some.address.fake.com \
    MIRRORCACHE_REDIRECT_VPN=some.address.fake.vpn.us \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $rs $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo -n 123 > $x/dt/folder1/file2.1.dat
    $x/start
done

# check rsync module is up properly
$rs/ls_dt

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove folder1/file1.1.dt from ap8
rm $ap8/dt/folder1/file2.1.dat

# first request redirected to MIRRORCACHE_REDIRECT, eventhough files are not there
$mc/curl -I /download/folder1/file2.1.dat | grep fake.com
$mc/curl -H 'X-Forwarded-For: 10.0.1.1' -I /download/folder1/file2.1.dat | grep fake.vpn.us

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/sql "select * from file"
test 0 == $($mc/db/sql "select size from file where name = 'file1.1.dat'")
test 3 == $($mc/db/sql "select size from file where name = 'file2.1.dat'")
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -I /download/folder1/file2.1.dat | grep $($ap7/print_address)

$mc/curl -H "Accept: */*, application/metalink+xml" /download/folder1/file2.1.dat | grep '<size>3</size>'

mv $ap7/dt/folder1/file2.1.dat $ap8/dt/folder1/
echo -n 123456789 > $rs/dt/folder1/file2.1.dat

# gets redirected to root again
$mc/curl -I /download/folder1/file2.1.dat | grep fake.com

# call incorrect file to force new sync
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# check correct file size in DB
test 9 == $($mc/db/sql "select max(size) from file where name = 'file2.1.dat'")

# reports correct size in metalink
$mc/curl -H "Accept: */*, application/metalink+xml" /download/folder1/file2.1.dat | grep '<size>9</size>'

# still redirects to root because size differs
$mc/curl -I /download/folder1/file2.1.dat | grep fake.com

# update file on ap8
cp $rs/dt/folder1/file2.1.dat $ap8/dt/folder1/

# now redirects to ap8
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap8/print_address)

# now add new file everywhere
for x in $rs $ap7 $ap8; do
    touch $x/dt/folder1/file3.1.dat
done

# first request will miss
$mc/curl -I /download/folder1/file3.1.dat | grep fake.com

# force rescan
# $mc/backstage/job mirror_scan_schedule_from_path_errors
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
# now expect to hit
$mc/curl -I /download/folder1/file3.1.dat | grep -E "$(ap8/print_address)|$($ap7/print_address)"

# now add new file only on main server and make sure it doesn't try to redirect
touch $rs/dt/folder1/file4.dat

$mc/curl -I /download/folder1/file4.dat | grep fake.com
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

test 2 == $($mc/db/sql "select count(*) from folder_diff_server")

cnt="$($mc/db/sql 'select max(id) from audit_event')"

$mc/curl -I /download/folder1/file4.dat

# it shouldn't try to probe yet, because scanner didn't find files on the mirrors
$mc/sql_test 0 == "select count(*) from audit_event where name = 'mirror_path_error' and id > $cnt"

for x in $rs $ap7 $ap8; do
    mkdir $x/dt/folder1/folder11
    touch $x/dt/folder1/folder11/file1.1.dat
done

# this is needed for schedule jobs to retry on next shoot
$mc/curl -I /download/folder1/folder11/file1.1.dat
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -I /download/folder1/folder11/file1.1.dat | grep -E "$(ap8/print_address)|$($ap7/print_address)"

$mc/curl /download/folder1/folder11/ | grep file1.1.dat


$mc/curl /download/folder1?status=all | grep '"recent":2'| grep '"not_scanned":0' | grep '"outdated":0'
$mc/curl /download/folder1?status=recent | grep $($ap7/print_address) | grep $($ap8/print_address)
test {} == $($mc/curl /download/folder1?status=outdated)
test {} == $($mc/curl /download/folder1?status=not_scanned)

##################################
# let's test path distortions
# remember number of folders in DB
cnt=$($mc/db/sql "select count(*) from folder")
$mc/curl -I /download//folder1//file1.1.dat
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
test $cnt == $($mc/db/sql "select count(*) from folder")

$mc/curl -I /download//folder1//file1.1.dat              | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download//folder1///file1.1.dat             | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download/./folder1/././file1.1.dat          | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download/./folder1/../folder1/./file1.1.dat | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
##################################



##################################
# test file with colon ':'
for x in $rs $ap7 $ap8; do
    touch $x/dt/folder1/file:4.dat
done

# first request will miss
$mc/curl -I /download/folder1/file:4.dat | grep fake.com

# force rescan
$mc/backstage/job folder_sync_schedule_from_misses
# $mc/backstage/job mirror_scan_schedule_from_path_errors
$mc/backstage/shoot
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job folder_sync_schedule
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
# now expect to hit
$mc/curl /download/folder1/ | grep file1.1.dat
$mc/curl /download/folder1/ | grep file:4.dat
$mc/curl -I /download/folder1/file:4.dat | grep -E "$($ap8/print_address)|$(ap7*/print_address)"
##################################


