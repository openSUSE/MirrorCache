#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary (same DB as hq)
# 8 - ASIA subsidiary

# hq mirrors: ap1 ap2
# na mirrors: ap3 ap4
# eu mirrors: ap5 ap6
# as mirrors: ap7 ap8

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{project1,project2}/{folder1,folder2,folder3}
    echo $x/dt/{project1,project2}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    eval mc$i=$x
done

for i in 1 2 3 4 5 6 7 8; do
    x=$(environ ap$i)
    mkdir -p $x/dt/{project1,project2}/{folder1,folder2,folder3}
    echo $x/dt/{project1,project2}/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
    eval ap$i=$x
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/sql "insert into subsidiary(hostname,region,local) select '$eu_address','eu','t'"
$mc9/sql "insert into subsidiary(hostname,region) select '$as_address','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','','t','br','sa'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','','t','br','sa'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','de','eu'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','dk','eu'"

$mc9/start

$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','t','us','na'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','ca','na'"

rm -r $mc7/db
ln -s $mc9/db $mc7/db
$mc7/start

$mc8/start
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','jp','as'"
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','jp','as'"

for i in 6 8 9; do
    mc$i/sql "insert into project(name,path) select 'proj1','/project1'"
    mc$i/sql "insert into project(name,path) select 'proj 2','/project2'"
    mc$i/backstage/job -e folder_sync -a '["/project1/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/project1/folder1"]'
    mc$i/backstage/job -e folder_sync -a '["/project1/folder2"]'
    mc$i/backstage/job -e mirror_scan -a '["/project1/folder2"]'
    mc$i/backstage/job -e folder_sync -a '["/project2/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/project2/folder1"]'
    mc$i/backstage/shoot
    mc$i/backstage/job mirror_probe_projects
    mc$i/backstage/job -e report -a '["once"]'
    mc$i/backstage/shoot
done

echo project1 to eu if we contacted hq from na
$mc9/sql "update project set redirect = 'na:$eu_address/download' where id = 1"
echo project2 to na even if we contacted hq from as or eu
$mc9/sql "update project set redirect = 'as:$na_address/download;eu:$na_address/download' where id = 2"
echo test project1 redirects
$mc9/curl --interface $na_interface -I  /download/project1/folder1/file1.1.dat | grep "$eu_address"
$mc9/curl --interface $eu_interface -I  /download/project1/folder1/file1.1.dat | grep "$eu_address"

echo test project2 redirects
$mc9/curl --interface $eu_interface -I  /download/project2/folder1/file1.1.dat | grep "$na_address"
$mc9/curl --interface $as_interface -I  /download/project2/folder1/file1.1.dat | grep "$na_address"
$mc9/curl --interface $as_interface -IL /download/project2/folder1/file1.1.dat | grep -E "$($ap3/print_address)|$($ap4/print_address)"
$mc9/curl --interface $na_interface -I  /download/project2/folder1/file1.1.dat | grep "$na_address"

echo "Let's pretend proj 2 has no good mirrors in as and we redirect all requests from it to na subsidiary"
$mc8/sql "update project set redirect = '$na_address/download' where id = 2"

echo project1 redirects to regular mirror
$mc8/curl -I /download/project1/folder1/file1.1.dat | grep -E "$($ap7/print_address)|$($ap8/print_address)"

echo project2 redirects to na
$mc8/curl -I /download/project2/folder1/file1.1.dat | grep $na_address/download/project2/folder1/file1.1.dat
$mc8/curl -IL /download/project2/folder1/file1.1.dat | grep -E "$($ap3/print_address)|$($ap4/print_address)"


# all countries present in report
$mc9/curl /rest/repmirror \
          | grep '"country":"br"' \
          | grep '"country":"de"' \
          | grep '"country":"dk"' \
          | grep '"country":"ca"' \
          | grep '"country":"us"' \
          | grep '"country":"jp"' \
          | grep -F '"region":"na (http:\/\/127.0.0.1:3160)"'

allmirrorspattern="$(ap1/print_address)"
for i in {2..8}; do
    x=ap$i
    allmirrorspattern="$allmirrorspattern|$($x/print_address)"
done

# all mirrors are mentioned in html report
test 8 == $($mc9/curl -i /report/mirrors | grep -A500 '200 OK' | grep -Eo $allmirrorspattern | sort | uniq | wc -l)

echo collect report when one of the instances is down
$mc6/stop

$mc9/backstage/job mirror_probe_projects
$mc9/backstage/job -e report -a '["once"]'
$mc9/backstage/shoot

$mc9/curl /rest/repmirror \
          | grep '"country":"br"' \
          | grep '"country":"de"' \
          | grep '"country":"dk"' \
          | grep '"country":"ca"' \
          | grep '"country":"us"' \
          | grep '"country":"jp"' \
          | grep -F '"region":"na (http:\/\/127.0.0.1:3160)"'

# all mirrors are mentioned in html report
test 8 == $($mc9/curl -i /report/mirrors | grep -A500 '200 OK' | grep -Eo $allmirrorspattern | sort | uniq | wc -l)

echo also when the main db is down
$mc9/db/stop

$mc9/curl /rest/repmirror \
          | grep '"country":"br"' \
          | grep '"country":"de"' \
          | grep '"country":"dk"' \
          | grep '"country":"ca"' \
          | grep '"country":"us"' \
          | grep '"country":"jp"' \
          | grep -F '"region":"na (http:\/\/127.0.0.1:3160)"'

# all mirrors are mentioned in html report
test 8 == $($mc9/curl -i /report/mirrors | grep -A500 '200 OK' | grep -Eo $allmirrorspattern | sort | uniq | wc -l)

echo success
