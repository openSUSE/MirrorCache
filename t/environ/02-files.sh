#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
$mc/gen_env MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
            MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

unversionedfiles="
    Leap-15.3.aarch64-libvirt_aarch64.box
    Leap-15.3.aarch64-libvirt_aarch64.box.sha256.asc
    Leap-15.3.x86_64-libvirt.box.sha256
    openSUSE-Leap-15.3-ARM-E20-efi.aarch64.raw.xz.sha256.asc
    openSUSE-Leap-15.3-NET-x86_64.iso
"

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/folder1/file1.dat | xargs -n 1 touch
    mkdir -p $x/dt/folder1.11test/
    for f in $unversionedfiles; do
        str=1
        [ $x != $mc ] || str=11
        echo $str > $x/dt/folder1.11test/$f
    done
done

$ap7/start
$ap8/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove a file from one mirror
rm $ap8/dt/folder1/file2.1.dat
# this file is different size on one mirrors
echo 1 > $ap8/dt/folder1/file1.dat

# force scan
$mc/curl -I /download/folder1/file2.1.dat
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/db/sql "select * from file"
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -I /download/folder1/file2.1.dat | grep 302
$mc/curl -I /download/folder1/file1.dat   | grep 302

mv $ap7/dt/folder1/file2.1.dat $ap8/dt/folder1/
mv $ap8/dt/folder1/file1.dat $ap7/dt/folder1/

$mc/curl -I /download/folder1/file2.1.dat?PEDANTIC=0 | grep 302
$mc/curl -I /download/folder1/file2.1.dat?PEDANTIC=1 | grep 200
# file1 isn't considered versioned, so pedantic mode is automatic
$mc/curl -I /download/folder1/file1.dat | grep 200

# make root the same size of folder1/file1.dat
echo 1 > $mc/dt/folder1/file1.dat

$mc/backstage/job mirror_scan_schedule_from_misses
$mc/backstage/shoot

$mc/curl -I /download/folder1/file2.1.dat | grep 302
$mc/curl -I /download/folder1/file1.1.dat | grep 302
$mc/curl -I /download/folder1/file1.dat   | grep 302

# now add new file everywhere
for x in $mc $ap7 $ap8; do
    touch $x/dt/folder1/file3.1.dat
done

# first request will miss
$mc/curl -I /download/folder1/file3.1.dat | grep 200

# force rescan
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot
# now expect to hit
$mc/curl -I /download/folder1/file3.1.dat | grep 302

# now add new file only on main server and make sure it doesn't try to redirect
touch $mc/dt/folder2/file4.dat

$mc/curl -I /download/folder2/file4.dat | grep 200
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot

test 4 == $($mc/db/sql "select count(*) from folder_diff_server")

cnt="$($mc/db/sql "select max(id) from stat")"

$mc/curl -I /download/folder1/file2.1.dat | grep 302

# it shouldn't try to reach file on mirrors yet, because scanner didn't find files
test 0 == $($mc/db/sql "select count(*) from stat where mirror_id = -1 and file_id is not NULL and id > $cnt")

$mc/curl -I /download/folder2/file4.dat | grep 200
# now an error must be logged
test 1 == $($mc/db/sql "select count(*) from stat where mirror_id = -1 and file_id is not NULL and id > $cnt")

##################################
# let's test path distortions
# remember number of folders in DB
cnt=$($mc/db/sql "select count(*) from folder")
$mc/curl -I /download//folder1//file1.1.dat
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot
test $cnt == $($mc/db/sql -t -c "select count(*) from folder" mc_test)

$mc/curl -I /download//folder1//file1.1.dat              | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download//folder1///file1.1.dat             | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download/./folder1/././file1.1.dat          | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
$mc/curl -I /download/./folder1/../folder1/./file1.1.dat | grep -C 10 -P '[^/]/folder1/file1.1.dat' | grep 302
##################################

# now add media.1/media
for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/folder1/media.1
    echo CONTENT1 > $x/dt/folder1/media.1/file1.1.dat
    echo CONTENT2 > $x/dt/folder1/media.1/media
done

$mc/curl -I /download/folder1/media.1/file1.1.dat
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot

# requests to media.1/* are not redirected to a mirror
$mc/curl -i /download/folder1/media.1/file1.1.dat.metalink | grep -v location
$mc/curl -i -H 'Accept: */*, application/metalink+xml' /download/folder1/media.1/file1.1.dat| grep -v location

test -z "$($mc/curl -i -H 'Accept: */*, application/metalink+xml' /download/folder1/media.1/media | grep location)" || FAIL media.1/media must not return metalink
$mc/curl -iL -H 'Accept: */*, application/metalink+xml' /download/folder1/media.1/media | grep CONTENT2


#####################################
# test PEDANTCI is on for unversioned files
$mc/backstage/job -e folder_sync -a '["/folder1.11test"]'
$mc/backstage/job -e mirror_scan -a '["/folder1.11test","us"]'
$mc/backstage/shoot

for f in $unversionedfiles; do
    $mc/curl -I /download/folder1.11test/$f | grep 200
    # sha256 must be served from root
    [[ $f =~ sha256 ]] || $mc/curl -I /download/folder1.11test/$f?PEDANTIC=0 | grep 302
done
