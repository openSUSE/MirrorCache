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
touch $root/dt/folder1/repodata/repomd.xml
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
curl -Is --interface $eu_interface http://$hq_address/folder1/repodata/repomd.xml     | grep -C 30 '200 OK' | grep "X-Geoip-Redir: http://euaddress.net"
curl -Is --interface $eu_interface http://$hq_address/folder1/repodata/repomd.xml.asc | grep -C 30 '200 OK' | grep "X-Geoip-Redir: http://euaddress.net"

mc9/curl --interface 127.0.0.5 /folder1/repodata/file1.dat.metalink | grep 'origin="http://127.0.0.1:3190/folder1/repodata/file1.dat.metalink"'
