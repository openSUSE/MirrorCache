#!lib/test-in-container-environ.sh
set -ex

# root : ap9

# mc environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary

root=$(environ ap9)

mkdir -p $root/dt/{folder1,folder2,folder3}
echo $root/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
mkdir $root/dt/folder1/repodata/
touch $root/dt/folder1/repodata/file1.dat
echo repomdcontent > $root/dt/folder1/repodata/repomd.xml
touch $root/dt/folder1/repodata/repomd.xml.asc

$root/start

mc9=$(environ mc9 $(pwd))
$mc9/gen_env "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'" \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0 \
    MIRRORCACHE_ROOT=http://$($root/print_address) \
    MIRRORCACHE_ROOT_NFS=$root/dt

# deploy db
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region) select 'naaddress.com','na'"
$mc9/sql "insert into subsidiary(hostname,region) select 'euaddress.net','eu'"
$mc9/start

$mc9/backstage/job -e folder_sync -a '["/folder1/repodata"]'
$mc9/backstage/job -e mirror_scan -a '["/folder1/repodata"]'
$mc9/backstage/shoot

hq_address=$(mc9/print_address)
eu_interface=127.0.0.3

# repodata/repomd.xml is served from root even when asked from EU
curl -si --interface $eu_interface http://$hq_address/download/folder1/repodata/repomd.xml | grep -A20 '200 OK' | grep repomdcontent
# repodata/repomd.xml is served even when DB is down
$mc9/db/stop
curl -si --interface $eu_interface http://$hq_address/download/folder1/repodata/repomd.xml | grep -A20 '200 OK' | grep repomdcontent


curl -si --interface $eu_interface http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>euaddress.net</host>"
curl -si                           http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>naaddress.com</host>"

curl -sI --interface 127.0.0.24    http://$hq_address/geoip     | grep '204 No Content'

$mc9/db/start
$mc9/curl --interface 127.0.0.5 /folder1/repodata/file1.dat.metalink | grep 'origin="http://127.0.0.1:3190/folder1/repodata/file1.dat.metalink"'
