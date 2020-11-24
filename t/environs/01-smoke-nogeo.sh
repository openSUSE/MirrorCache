#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

export MIRRORCACHE_CITY_MMDB=""
mc9*/start.sh
mc9*/status.sh

./environ.sh ap8-system2
./environ.sh ap7-system2

for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap7*/status.sh >& /dev/null || ap7*/start.sh
ap7*/curl.sh folder1/ | grep file1.dat

ap8*/status.sh >& /dev/null || ap8*/start.sh
ap8*/curl.sh folder1/ | grep file1.dat


pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','de',''" mc_test

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from minion_jobs order by id" mc_test

curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep -C10 302 | grep -E "($(ap7*/print_address.sh)|$(ap8*/print_address.sh))"

###################################
# test files are removed properly
rm mc9/dt/folder1/file1.dat

# resync the folder
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/job.sh -e mirror_probe -a '["/folder1"]'
mc9*/backstage/shoot.sh

curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat || :
if curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat ; then 
    fail file1.dat was deleted
fi
