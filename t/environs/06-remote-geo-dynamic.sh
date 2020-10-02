#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

for x in ap6-system2 ap7-system2 ap8-system2 ap9-system2; do
    ./environ.sh $x
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start.sh
done

export MIRRORCACHE_ROOT=http://$(ap6*/print_address.sh)
mc9*/start.sh
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','/','t','de',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.4:1324','/','t','cn',''" mc_test

# we need to request file from two countries, so all mirrors will be scanned
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat

test 0 == "$(grep -c Poll mc9/.cerr)"

# currently it takes some time, need to improve somehow
sleep 20

curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1324
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1314
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1304
test 0 == "$(grep -c Poll mc9/.cerr)"
