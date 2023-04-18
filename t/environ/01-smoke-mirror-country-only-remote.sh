#!lib/test-in-container-environ.sh
set -ex

FAKEURL="notexists${RANDOM}.com"
FAKEURL2="notexists2${RANDOM}.com"

ap9=$(environ ap9)

mc=$(environ mc $(pwd))

$mc/gen_env \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_METALINK_GREEDY=3 \
    MIRRORCACHE_REDIRECT=$FAKEURL2

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap9/start
$ap9/curl /folder1/ | grep file1.1.dat

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat
rm $ap7/dt/folder1/file2.1.dat # remove a file from ap7

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"


$mc/sql "insert into server_capability_declaration(server_id, capability, enabled, extra) select 2, 'country', 't', 'de|uk'";

$mc/curl -Is /download/folder1/file1.1.dat.mirrorlist

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=de | grep -C10 302 | grep "$($ap8/print_address)"
$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=us | grep -C10 302 | grep "$($ap7/print_address)"
echo we have to redirect dk to us, because ap8 serves only de and uk
$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=dk | grep -C10 302 | grep "$($ap7/print_address)"
echo but ap8 still serves uk
$mc/curl -I /download/folder1/file1.1.dat?COUNTRY=uk | grep -C10 302 | grep "$($ap8/print_address)"

echo success
