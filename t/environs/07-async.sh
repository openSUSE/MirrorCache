#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

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


mc9*/backstage/start.sh
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','de',''" mc_test

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat

sleep 5
pg9*/sql.sh -c "select * from minion_jobs order by id" mc_test

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 \
   || ( echo "retry 1" && sleep 5 && curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 ) \
   || ( echo "retry 2" && sleep 5 && curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 ) \
   || ( echo "retry 3" && sleep 5 && curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 ) \
   || ( echo "retry 4" && sleep 5 && curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 ) \
   || ( echo "retry 5" && sleep 5 && curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302 )

pg9*/sql.sh -t -c "select count(*) from minion_jobs where task='folder_sync'" mc_test
sleep 15
pg9*/sql.sh -t -c "select count(*) from minion_jobs where task='folder_sync'" mc_test
