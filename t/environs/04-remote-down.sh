#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
./environ.sh ap9-system2
mc9*/configure_db.sh pg9
export MIRRORCACHE_ROOT=http://$(ap9*/print_address.sh)
export MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

./environ.sh ap8-system2
./environ.sh ap7-system2

for x in ap7-system2 ap8-system2 ap9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    mkdir -p $x/dt/folder1/repodata
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    touch $x/dt/folder1/repodata/repomd.xml
    $x/start.sh
done

mc9*/start.sh
mc9*/status.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

# first request redirected to root
curl -Is http://127.0.0.1:3190/download/folder1/repodata/repomd.xml | grep $(ap9*/print_address.sh)
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap9*/print_address.sh)

# remove folder1/file2.dt from ap8
rm ap8-system2/dt/folder1/file2.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap7*/print_address.sh)
echo repomd is still taken from the root
curl -Is http://127.0.0.1:3190/download/folder1/repodata/repomd.xml | grep $(ap9*/print_address.sh)

# shutdown root
ap9*/stop.sh

if ap9*/status.sh ; then
    fail Root apache must be down
fi

echo mc properly redirects when root is down
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap7*/print_address.sh)

# since root is unavailable repomd is taken from a mirror
curl -Is http://127.0.0.1:3190/download/folder1/repodata/repomd.xml | grep -E "$(ap7*/print_address.sh)|$(ap8*/print_address.sh)"
ap9*/start.sh
ap9*/status.sh
# since root is up again, redirect to root
curl -Is http://127.0.0.1:3190/download/folder1/repodata/repomd.xml | grep $(ap9*/print_address.sh)
