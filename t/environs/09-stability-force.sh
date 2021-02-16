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


pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','us',''" mc_test

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat

mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

# check redirection works
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302

# now shut down ap7 and do probe
ap7*/stop.sh
mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/shoot.sh

# check that ap7 is marked correspondingly in server_capability_check
test  1 == $(pg9*/sql.sh -t -c "select sum(case when success then 0 else 1 end) from server_capability_check where server_id=1 and capability='http'" mc_test)

# add 4 more failures in past
pg9*/sql.sh -t -c "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'" mc_test
pg9*/sql.sh -t -c "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'" mc_test
pg9*/sql.sh -t -c "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'" mc_test
pg9*/sql.sh -t -c "insert into server_capability_check(server_id, capability, success, dt) select 1, 'http', 'f', (select min(dt) from server_capability_check) - interval '15 min'" mc_test

# make sure we added properly
test 5 == $(pg9*/sql.sh -t -c "select sum(case when success then 0 else 1 end) from server_capability_check where server_id=1 and capability='http'" mc_test)

ap7*/stop.sh
mc9*/backstage/job.sh -e mirror_force_downs
mc9*/backstage/shoot.sh

test 1 == $(pg9*/sql.sh -t -c "select count(*) from server_capability_force where server_id=1 and capability='http'" mc_test)

# age entry, so next job will consider it
pg9*/sql.sh -t -c "update server_capability_force set dt = dt - interval '3 hour'" mc_test

# now start back ap7 and shut down ap8 but ap7 is not redirected, because it is force disabled
ap7*/start.sh
ap8*/stop.sh
mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep -v $(ap7*/print_address.sh)

# now scan those mirrors which were force disabled
mc9*/backstage/job.sh -e mirror_force_ups
mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/shoot.sh

# ap7 now should serve the request
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep $(ap7*/print_address.sh)
