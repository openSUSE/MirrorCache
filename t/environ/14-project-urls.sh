#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_BRANDING=openSUSE

$mc/start

ap8=$(environ ap8)
ap7=$(environ ap7)
ap6=$(environ ap6)
ap5=$(environ ap5)
ap4=$(environ ap4)

for x in $mc $ap7 $ap8 $ap6 $ap5 $ap4; do
    mkdir -p $x/dt/project1/{folder1,folder2,folder3}
    echo $x/dt/project1/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap4/start
$ap5/start
$ap6/start
$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','/','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','cn','as'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','jp','as'"

$mc/sql "insert into project(name,path) select 'proj1','/project1'"

$mc/backstage/job -e folder_sync -a '["/project1/folder1"]'
$mc/backstage/job -e mirror_scan -a '["/project1/folder1"]'
$mc/backstage/shoot

$mc/backstage/job mirror_probe_projects
$mc/backstage/shoot

# fill server_stability to see more in the report
$mc/sql "insert into server_stability select id, 'http', now(), 1000 from server"
# change urldir only for the report (the mirrors will appear as green until next scan)
$mc/sql "update server set urldir = '/dist'  where hostname = '$($ap7/print_address)'"
$mc/sql "update server set urldir = '/dist/' where hostname = '$($ap8/print_address)'"

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repmirror | grep -oF '"http_url":"http:\/\/'$($ap7/print_address)'\/dist\/"'
$mc/curl /rest/repmirror | grep -oF '"http_url":"http:\/\/'$($ap8/print_address)'\/dist\/"'
$mc/curl /rest/repmirror | grep -oF '"http_url":"http:\/\/'$($ap5/print_address)'\/"'

echo success
