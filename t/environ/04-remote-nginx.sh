#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ng9=$(environ ng9)

MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=http://$($ng9/print_address) \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

ng8=$(environ ng8)
ng7=$(environ ng7)

for x in $ng7 $ng8 $ng9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo -n 0123456789 > $x/dt/folder1/file2.1.dat
    $x/start
done

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ng7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ng8/print_address)','','t','us','na'"

# remove folder1/file1.1.dt from ng8
rm $ng8/dt/folder1/file2.1.dat

# first request redirected to root
$mc/curl -I /download/folder1/file2.1.dat | grep $($ng9/print_address)

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/sql "select * from file"
test 0  == $($mc/db/sql "select size from file where name='file1.1.dat'")
test 10 == $($mc/db/sql "select size from file where name='file2.1.dat'")

test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -I /download/folder1/file2.1.dat | grep $($ng7/print_address)

mv $ng7/dt/folder1/file2.1.dat $ng8/dt/folder1/

# gets redirected to root again
$mc/curl -I /download/folder1/file2.1.dat | grep $($ng9/print_address)

# $mc/backstage/job mirror_scan_schedule_from_path_errors
# $mc/backstage/shoot
# $mc/backstage/job mirror_scan_schedule
$mc/backstage/job -e mirror_scan -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -H "Accept: */*, application/metalink+xml" /download/folder1/file2.1.dat | grep $($ng9/print_address)

# now redirects to ng8
$mc/curl -I /download/folder1/file2.1.dat | grep $($ng8/print_address)

# now add new file everywhere
for x in $ng9 $ng7 $ng8; do
    touch $x/dt/folder1/file3.1.dat
done

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot
# now expect to hit
$mc/curl -I /download/folder1/file3.1.dat | grep -E "$($ng8/print_address)|$($ng7/print_address)"

# now add new file only on main server and make sure it doesn't try to redirect
touch $ng9/dt/folder1/file4.dat

$mc/curl -I /download/folder1/file4.dat | grep -E "$($ng9/print_address)"
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

test 2 == $($mc/db/sql "select count(*) from folder_diff_server")

cnt="$($mc/db/sql "select count(*) from audit_event")"

$mc/curl -I /download/folder1/file4.dat

# it shouldn't try to probe yet, because scanner didn't find files on the mirrors
test 0 == $($mc/db/sql "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt")

for x in $ng9 $ng7 $ng8; do
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

$mc/curl -I /download/folder1/folder11/file1.1.dat | grep -E "$($ng7/print_address)|$($ng8/print_address)"
$mc/curl /download/folder1/folder11/ | grep file1.1.dat


$mc/curl /download/folder1?status=all | grep '"recent":2'| grep '"not_scanned":0' | grep '"outdated":0'
$mc/curl /download/folder1?status=recent | grep $($ng7/print_address) | grep $($ng8/print_address)
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
for x in $ng9 $ng7 $ng8; do
    touch $x/dt/folder1/file:4.dat
done

# first request will miss
$mc/curl -I /download/folder1/file:4.dat | grep -E "$($ng9/print_address)"

$mc/db/sql "select s.id, s.hostname, fd.id, fd.hash, fl.name, fd.dt, fl.dt
from
folder_diff fd
join folder_diff_server fds on fd.id = fds.folder_diff_id
join server s on s.id = fds.server_id
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fdf.file_id = fl.id
left join folder f on fd.folder_id = f.id
order by f.id, s.id, fl.name
"

# force rescan
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/sql "select s.id, s.hostname, fd.id, fd.hash, fl.name, fd.dt, fl.dt
from
folder_diff fd
join folder_diff_server fds on fd.id = fds.folder_diff_id
join server s on s.id = fds.server_id
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fdf.file_id = fl.id
left join folder f on fd.folder_id = f.id
order by f.id, s.id, fl.name
"

# now expect to hit
$mc/curl /download/folder1/ | grep file1.1.dat
$mc/curl /download/folder1/ | grep file:4.dat
$mc/curl -I /download/folder1/file:4.dat | grep -E "$($ng8/print_address)|$(ng7*/print_address)"
##################################

f=0123456789012345678901234567890123456789.\(\#@~\)abcdefghijklmnoprst.dat

for x in $ng9 $ng7 $ng8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo -n 0123456789 > $x/dt/folder1/$f
done

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl /download/folder1/ | grep -B1 $f | grep '10 Byte'
