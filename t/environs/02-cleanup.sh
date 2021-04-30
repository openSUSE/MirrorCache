#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

export MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0
mc9*/start.sh
mc9*/status.sh

./environ.sh ap8-system2
./environ.sh ap7-system2

for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap7*/status.sh >& /dev/null || ap7*/start.sh
ap8*/status.sh >& /dev/null || ap8*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

# remove a file from one mirror
rm ap8-system2/dt/folder1/file2.dat

# force scan
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

# update dt column to make entries look older
pg9*/sql.sh -t -c "update folder_diff set dt = dt - interval '5 day'" mc_test
pg9*/sql.sh -t -c "update server_capability_check set dt = dt - interval '5 day' where server_id = 1" mc_test

# now add new files on some mirrors to generate diff
touch {mc9,ap7-system2}/dt/folder1/file3.dat
touch {mc9,ap8-system2}/dt/folder1/file4.dat

# force rescan
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

test 4 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 4 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)
test 8 == $(pg9*/sql.sh -t -c "select count(*) from server_capability_check" mc_test)

# run cleanup job
mc9*/backstage/job.sh cleanup
mc9*/backstage/shoot.sh

# test for reduced number of rows
test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 3 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)
test 4 == $(pg9*/sql.sh -t -c "select count(*) from server_capability_check" mc_test)
