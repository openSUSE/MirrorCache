#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

# $mc/gen_env MIRRORCACHE_BRANDING=openSUSE

$mc/start

ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)
ap5=$(environ ap5)
ap4=$(environ ap4)
ap3=$(environ ap3)

for x in $mc $ap7 $ap8 $ap6 $ap5 $ap4 $ap3; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/project1/{folder1,folder2,folder3}
    mkdir -p $x/dt/project2/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project1/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo $x/dt/project2/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap3/start
$ap4/start
$ap5/start
$ap6/start
$ap7/start
$ap8/start

# remove some files and folders
rm $ap7/dt/project1/folder2/file2.1.dat
rm $ap7/dt/project2/folder2/file2.1.dat
rm -r $ap5/dt/project2/folder2/
rm -r $ap5/dt/project1/
rm -r $ap4/dt/project2/

$mc/sql "insert into server(hostname,sponsor,sponsor_url,urldir,enabled,country,region) select '$($ap6/print_address)','sponsor1 very long name inc Universitaties Subdivision','www.sponsor.org','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','f','jp','as'"

$mc/sql "insert into project(name,path) select '2.0 1','/project2/folder1'"
$mc/sql "insert into project(name,path) select 'proj1','/project1'"
$mc/sql "insert into project(name,path) select '2.0 2','/project2/folder2'"

echo add extra info for the report
$mc/sql "insert into server_note(dt,hostname,kind,msg) select now(), '$($ap7/print_address)','Ftp', 'ftp://ftp.ap7.com/opensuse'"
$mc/sql "insert into server_note(dt,hostname,kind,msg) select now(), '$($ap6/print_address)','Ftp', 'ftp://ftp.ap6.com/opensuse'"
sleep 1
$mc/sql "insert into server_note(dt,hostname,kind,msg) select now(), '$($ap7/print_address)','Rsync', 'rsync://rsync.ap7.com/opensuse'"
$mc/sql "insert into server_note(dt,hostname,kind,msg) select now(), '$($ap6/print_address)','Rsync', 'rsync://rsync.ap6.com/opensuse'"

$mc/sql "insert into server_stability(dt,server_id,rating,capability) select now(), 1, 1000, 'https'"
$mc/sql "insert into server_stability(dt,server_id,rating,capability) select now(), 1, 1000, 'http'"
$mc/sql "insert into server_stability(dt,server_id,rating,capability) select now(), 1, 1000, 'ipv6'"
$mc/sql "insert into server_stability(dt,server_id,rating,capability) select now(), 2, 0, 'https'"
$mc/sql "insert into server_stability(dt,server_id,rating,capability) select now(), 2, 100, 'http'"


$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/job -e folder_sync -a '["/project1/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder2"]'
$mc/backstage/job -e folder_sync -a '["/project2/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder1"]'
$mc/backstage/job -e folder_sync -a '["/project2/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder2"]'
$mc/backstage/shoot

$mc/backstage/job mirror_probe_projects
$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /report/mirrors | tidy --drop-empty-elements no | \
   grep -A4 -F '<div class="repo">' | \
   grep -A2 -F '"http://127.0.0.1:1304/project2/folder2">' | \
   grep -C3 '\b2\b' | \
   grep -C3 -F '</a>'


rc=0
# no disabled mirror in the report
$mc/curl /report/mirrors | grep $($ap3/print_address) || rc=$?
test $rc -gt 0

$mc/curl /report/mirrors | grep 'generated at'

# update priority to negative and make sure it is not in the report any longer
$mc/sql "update project set prio = -1 where name like '2.0%'";
$mc/stop
$mc/start

echo check 2.0 is no longer in the report
rc=0
$mc/curl /report/mirrors | grep -F '2.0' || rc=$?
test $rc -gt 0

echo check 2.0 link has no cn server, because it has nothing from 2.0
rc=0
$mc/curl /report/mirrors/proj1 | grep -F "$($ap5/print_address)" || rc=$?
test $rc -gt 0

echo success
