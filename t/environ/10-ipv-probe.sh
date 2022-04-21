#!lib/test-in-container-environ.sh

# TODO: THIS TEST REQUIRES IPv6 enabled in DOCKER !!!

# Smoke test for https-only mirrors
set -ex

mc=$(environ mc $(pwd))

ipv4=$($mc/print_address)
new=${ipv4/127.0.0.1/[::]}
ipv6=${new/\[::\]/\[::1\]}
# should listen both ipv4 and ipv6
$mc/gen_env MOJO_LISTEN=http://$new

$mc/start
$mc/status

# this mirror will do only ipv6 ::1
ap8=$(environ ap8)
sed -i 's/Listen 1314/Listen [::1]:1314/' $ap8/httpd.conf
# this mirror will do only ipv4 127.0.0.1
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '[::1]:1314','','t','us','na'"

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot
$mc/sql_test "select 1 from server_capability_check where server_id=1 and capability='ipv6'"
$mc/sql_test "select 1 from server_capability_check where server_id=2 and capability='ipv4'"

# now explicitly force disable corresponding capabilities
$mc/sql "insert into server_capability_force(server_id,capability,dt) select 1,'ipv6',now()"
$mc/sql "insert into server_capability_force(server_id,capability,dt) select 2,'ipv4',now()"

$mc/curl -I /download/folder1/file1.1.dat # access file to schedule jobs

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# make sure it redirects to ipv4 and ipv6 as requested
curl -Is $ipv4/download/folder1/file1.1.dat | grep $($ap7/print_address)
curl -Is $ipv6/download/folder1/file1.1.dat | grep Location | grep ::1


# make sure order in metalink honorc ipv
curl -s $ipv4/download/folder1/file1.1.dat.metalink | grep -A1 $($ap7/print_address) | grep ::1
curl -s $ipv6/download/folder1/file1.1.dat.metalink | grep -A1 ::1 | grep $($ap7/print_address)

# make sure ipv is strict with IPV parameter
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV  | grep $($ap7/print_address)
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV4 | grep $($ap7/print_address)
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV6 | grep ::1

curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV  | grep ::1
curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV6 | grep ::1
curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV4 | grep $($ap7/print_address)

rc=0
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV  | grep ::1 || rc=$?
test $rc -gt 0
rc=0
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV4 | grep ::1 || rc=$?
test $rc -gt 0
rc=0
curl -s $ipv4/download/folder1/file1.1.dat.metalink?IPV6 | grep $($ap7/print_address) || rc=$?
test $rc -gt 0

rc=0
curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV  | grep $($ap7/print_address) || rc=$?
test $rc -gt 0
rc=0
curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV6 | grep $($ap7/print_address) || rc=$?
test $rc -gt 0
rc=0
curl -s $ipv6/download/folder1/file1.1.dat.metalink?IPV4 | grep file1.dat | grep ::1 || rc=$?
test $rc -gt 0
