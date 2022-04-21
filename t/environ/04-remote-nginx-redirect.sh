#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ng9=$(environ ng9)
ap9=$(environ ap9)

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=http://$($ng9/print_address) \
    MIRRORCACHE_REDIRECT=http://$($ap9/print_address) \
    MIRRORCACHE_REDIRECT_VPN=root.vpn.us \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

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

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ng7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,hostname_vpn,urldir,enabled,country,region) select 'non-vpn.us','$($ng8/print_address)','','t','us','na'"

# remove a file from ng8
rm $ng8/dt/folder1/file2.1.dat

# first request redirected to MIRRORCACHE_REDIRECT, eventhough files are not there
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap9/print_address)
# for 10.* addresses MIRRORCACHE_REDIRECT_VPN should be used
$mc/curl -H 'X-Forwarded-For: 10.0.1.1' -I /download/folder1/file2.1.dat | grep root.vpn.us

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -I /download/folder1/file2.1.dat | grep $($ng7/print_address)

mv $ng7/dt/folder1/file2.1.dat $ng8/dt/folder1/

# gets redirected to MIRRORCACHE_REDIRECT again, because MIRRORCACHE_PEDANTIC is set to 1
$mc/curl -I /download/folder1/file2.1.dat | grep $($ap9/print_address)

$mc/backstage/job mirror_scan_schedule_from_path_errors
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -H "Accept: */*, application/metalink+xml" /download/folder1/file2.1.dat | grep $($ap9/print_address)

$mc/curl -I /download/folder1/file2.1.dat?PEDANTIC=0 | grep non-vpn.us
# 10.* redirected to mirror.vpn.us
$mc/curl  -H 'X-Forwarded-For: 10.0.1.1' -I '/download/folder1/file2.1.dat?COUNTRY=us' | grep $($ng8/print_address)
