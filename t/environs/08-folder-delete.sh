#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

MIRRORCACHE_TEST_TRUST_AUTH=1 mc9*/start.sh
mc9*/status.sh

./environ.sh ap8-system2
./environ.sh ap7-system2

for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap7*/status.sh >& /dev/null || ap7*/start.sh
ap8*/status.sh >& /dev/null || ap8*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','us',''" mc_test

# remove folder1/file1.dt from ap8
rm ap8-system2/dt/folder1/file2.dat

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from file" mc_test
test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -X DELETE -Is http://127.0.0.1:3190/admin/folder_diff/1

test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder" mc_test)
test 0 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 0 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -X DELETE -Is http://127.0.0.1:3190/admin/folder/1
curl -X DELETE -Is http://127.0.0.1:3190/admin/folder/1

test 0 == $(pg9*/sql.sh -t -c "select count(*) from file" mc_test)
test 0 == $(pg9*/sql.sh -t -c "select count(*) from folder" mc_test)


######################################################################
# test automated database cleanup for folders that don't exist anymore
# create some entries in table folder
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl -Is http://127.0.0.1:3190/download/folder2/file1.dat
curl -Is http://127.0.0.1:3190/download/folder3/file1.dat
# force rescan
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

test 3 == $(pg9*/sql.sh -t -c "select count(*) from folder" mc_test)

rm -r mc9/dt/folder1
rm -r mc9/dt/folder2

# this is only for tests - the folder will be deleted only when
export MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT=3

mc9*/backstage/job.sh -e folder_sync -a '["/folder1"]'
mc9*/backstage/job.sh -e folder_sync -a '["/folder2"]'
mc9*/backstage/job.sh -e folder_sync -a '["/folder3"]'
mc9*/backstage/shoot.sh

# all folders must exist still
test 1 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder1' then 1 else 0 end) from folder" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder2' then 1 else 0 end) from folder" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder3' then 1 else 0 end) from folder" mc_test)

mc9*/backstage/job.sh -e folder_sync -a '["/folder1"]'
mc9*/backstage/shoot.sh

sleep 3s
mc9*/backstage/job.sh -e folder_sync -a '["/folder2"]'
mc9*/backstage/job.sh -e folder_sync -a '["/folder3"]'
mc9*/backstage/shoot.sh


pg9*/sql.sh -t -c "select * from minion_jobs where task = 'folder_sync'" mc_test

# folder1 is not removed yet because its failures were recorded too fast and MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT must be honored
test 1 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder1' then 1 else 0 end) from folder" mc_test)
# folder2 has been removed, because at least two jobs within MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT are failed
test 0 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder2' then 1 else 0 end) from folder" mc_test)
# folder3 shouldn't be touched
test 1 == $(pg9*/sql.sh -t -c "select sum(case when path='/folder3' then 1 else 0 end) from folder" mc_test)

