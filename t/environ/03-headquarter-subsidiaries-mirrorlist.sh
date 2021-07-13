#!lib/test-in-container-environ.sh
set -ex

# mc environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary

# hq mirros: ap1 ap2
# na mirros: ap3 ap4
# eu mirros: ap5 ap6

for i in 9 6 7; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    eval mc$i=$x
done

for i in 1 2 3 4 5 6; do
    x=$(environ ap$i)
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    eval ap$i=$x
    $x/start
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3

# deploy db
$mc9/gen_env "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/start
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','','t','jp','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','','t','jp','as'"

$mc6/gen_env MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','','t','us','na'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','','t','ca','na'"

$mc7/gen_env MIRRORCACHE_REGION=eu MIRRORCACHE_HEADQUARTER=$hq_address "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc7/start
$mc7/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','','t','de','eu'"
$mc7/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','','t','dk','eu'"

for i in 9 6 7; do
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/folder1"]'
    mc$i/backstage/shoot
done


curl -s "http://$na_address/folder1/file1.dat?mirrorlist&json"
curl -s "http://$eu_address/folder1/file1.dat?mirrorlist&json"

curl -s "http://$hq_address/rest/eu?file=/folder1/file1.dat" | grep -C50 $($ap5/print_address) | grep $($ap6/print_address)
curl -s "http://$hq_address/rest/na?file=/folder1/file1.dat" | grep -C50 $($ap3/print_address) | grep $($ap4/print_address)

curl -sL http://$hq_address/folder1/file1.dat.metalink | grep file1.dat
curl -sL --interface 127.0.0.4 http://$hq_address/folder1/file1.dat.metalink | grep file1.dat

curl -s http://$hq_address/folder1/file1.dat.mirrorlist | grep file1.dat
curl -s --interface $eu_interface http://$eu_address/folder1/file1.dat.mirrorlist | grep file1.dat
curl -s http://$hq_address/download/folder1/file2.dat.mirrorlist | grep file2.dat
curl -s --interface $eu_interface http://$eu_address/download/folder1/file2.dat.mirrorlist | grep file2.dat
