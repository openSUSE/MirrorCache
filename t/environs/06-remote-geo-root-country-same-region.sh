#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

for x in ap8-system2 ap9-system2; do
    ./environ.sh $x
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start.sh
done

export MIRRORCACHE_ROOT=http://$(ap9*/print_address.sh)
export MIRRORCACHE_STAT_FLUSH_COUNT=1
export MIRRORCACHE_ROOT_COUNTRY=de
export MIRRORCACHE_ROOT_LONGITUDE=11.07
mc9*/start.sh

CZ_ADDRESS=$(ap8*/print_address.sh)
DE_ADDRESS=$(ap9*/print_address.sh)

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region,lat,lng) select '$CZ_ADDRESS','','t','cz','eu',50.07,14.43" mc_test

mc9*/backstage/job.sh -e folder_sync -a '["/folder1"]'
mc9*/backstage/job.sh -e mirror_scan -a '["/folder1"]'
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=cz | grep $CZ_ADDRESS
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=de | grep $DE_ADDRESS

# use --interface to get latitude from the test geoip database
# 127.0.0.2 is US, so must be closer to de
curl --interface 127.0.0.2 -Is 'http://127.0.0.1:3190/download/folder1/file1.dat?REGION=eu' | grep $DE_ADDRESS
# 127.0.0.4 is CN, so must be closer to cz
curl --interface 127.0.0.4 -Is 'http://127.0.0.1:3190/download/folder1/file1.dat?REGION=eu' | grep $CZ_ADDRESS

# check order of the same in metalink file
curl --interface 127.0.0.2 -s 'http://127.0.0.1:3190/download/folder1/file1.dat.metalink?REGION=eu' | grep -A1 $DE_ADDRESS | grep $CZ_ADDRESS
curl --interface 127.0.0.4 -s 'http://127.0.0.1:3190/download/folder1/file1.dat.metalink?REGION=eu' | grep -A1 $CZ_ADDRESS | grep $DE_ADDRESS
