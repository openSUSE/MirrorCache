#!lib/test-in-container-environ.sh
set -exo pipefail

mc=$(environ mc $(pwd))

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

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','f','jp','as'"

$mc/sql "insert into project(name,path,etalon) select '2.0 1','/project2/folder1', 3"
$mc/sql "insert into project(name,path,etalon) select 'proj1','/project1', 3"
$mc/sql "insert into project(name,path,etalon) select '2.0 2','/project2/folder2', 3"

$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/job -e folder_sync -a '["/project1/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder2"]'
$mc/backstage/job -e folder_sync -a '["/project2/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder1"]'
$mc/backstage/job -e folder_sync -a '["/project2/folder2"]'
$mc/backstage/job -e mirror_scan -a '["/project2/folder2"]'
$mc/backstage/shoot

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /report/mirrors | tidy --drop-empty-elements no | \
   grep -A5 -F '<div class="repo">' | \
   grep -A4 -F '<a class="repouncertain"' | \
   grep -A3 -F '"diff in: /project2/folder2"' | \
   grep -A2 -F '"http://127.0.0.1:1304/project2/folder2">' | \
   grep -C3 '\b2\b' | \
   grep -C3 -F '</a>'


rc=0
# no disabled mirror in the report
$mc/curl /report/mirrors | grep $($ap3/print_address) || rc=$?
test $rc -gt 0

echo success
