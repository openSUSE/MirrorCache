#!lib/test-in-container-environ.sh
set -ex

# let all geo locations share the same db

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary
# 8 - ASIA subsidiary

# hq mirrors: ap1 ap2
# na mirrors: ap3 ap4
# eu mirrors: ap5 ap6
# as mirrors: ap7 ap8

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    mkdir $x/dt/folder1/media.1/
    touch $x/dt/folder1/media.1/media
    mkdir $x/dt/folder1/repodata/
    touch $x/dt/folder1/repodata/repomd.xml
    eval mc$i=$x
done

for i in 1 2 3 4 5 6 7 8; do
    x=$(environ ap$i)
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    mkdir $x/dt/folder1/media.1/
    touch $x/dt/folder1/media.1/media
    eval ap$i=$x
    $x/start
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'"
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/sql "insert into subsidiary(hostname,region) select '$as_address','as'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap1/print_address)','',1,'br','sa'"
$mc9/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap2/print_address)','',1,'br','sa'"
$mc9/start

$mc6/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'" MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address
rm -r $mc6/db
ln -s $mc9/db $mc6/db
$mc6/start
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap3/print_address)','',1,'us','na'"
$mc6/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap4/print_address)','',1,'ca','na'"

$mc7/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'" MIRRORCACHE_REGION=eu MIRRORCACHE_HEADQUARTER=$hq_address
rm -r $mc7/db
ln -s $mc9/db $mc7/db
$mc7/start
$mc7/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap5/print_address)','',1,'de','eu'"
$mc7/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap6/print_address)','',1,'dk','eu'"

$mc8/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2 folder3'" MIRRORCACHE_REGION=as MIRRORCACHE_HEADQUARTER=$hq_address
rm -r $mc8/db
ln -s $mc9/db $mc8/db
$mc8/start
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','',1,'jp','as'"
$mc8/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','',1,'jp','as'"

echo the root folder is not redirected
curl --interface $eu_interface -Is http://$hq_address/ | grep '200 OK'

for i in 9 6 7 8; do
    mc$i/backstage/job -e folder_sync -a '["/folder1"]'
    mc$i/backstage/job -e mirror_scan -a '["/folder1"]'
    mc$i/backstage/shoot
done

curl -s "http://$hq_address/rest/eu?file=/folder1/file1.1.dat" | grep -C50 $($ap5/print_address) | grep $($ap6/print_address)
curl -s "http://$hq_address/rest/na?file=/folder1/file1.1.dat" | grep -C50 $($ap3/print_address) | grep $($ap4/print_address)

curl -sL http://$hq_address/folder1/file1.1.dat.metalink | grep file1.1.dat
curl -sL --interface 127.0.0.4 http://$hq_address/folder1/file1.1.dat.metalink | grep file1.1.dat

curl -s http://$hq_address/folder1/file1.1.dat.mirrorlist | grep file1.1.dat
curl -s --interface $eu_interface http://$eu_address/folder1/file1.1.dat.mirrorlist | grep file1.1.dat
curl -s http://$hq_address/download/folder1/file2.1.dat.mirrorlist | grep file2.1.dat
curl -s --interface $eu_interface http://$eu_address/download/folder1/file2.1.dat.mirrorlist | grep file2.1.dat

# media.1/media and repomd is served from root even when asked from EU
curl -Is --interface $eu_interface http://$hq_address/folder1/media.1/media | grep 200
curl -Is --interface $eu_interface http://$hq_address/folder1/repodata/repomd.xml | grep 200

###########################################
# test table demand_mirrorlist:
# if mirrorlist was requested for known file - all countries will be scanned
mc9/backstage/job -e folder_sync -a '["/folder2"]'
mc9/backstage/shoot

curl -sL --interface $as_interface http://$hq_address/folder2/file1.1.dat.mirrorlist | grep 'file1.1.dat'
mc9/backstage/job -e mirror_scan_schedule_from_misses
mc9/backstage/job -e mirror_scan_schedule
mc9/backstage/shoot

curl -sL --interface $as_interface http://$hq_address/folder2/file1.1.dat.mirrorlist | grep -C10 $($ap1/print_address) | grep $($ap2/print_address)

test 2 == $(curl -sL --interface $as_interface http://$hq_address/folder2/file1.1.dat.mirrorlist?COUNTRY=br | grep -A5 'Mirrors which handle this country' | grep '(BR)' | wc -l)

