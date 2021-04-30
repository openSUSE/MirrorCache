#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
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

# log current audit_event count
cnt="$(pg9*/sql.sh -t -c "select count(*) from audit_event" mc_test)"

# make sure now it redirects to ap8
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap8*/print_address.sh)

# audit event shouldn't contain recent mirror_probe event, becuase we know that ap7 is not preferable because of recent probe error
test 0 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt" mc_test)

# now shut down ap8 and start ap7, then probe mirrors explicitly
ap8*/stop.sh
ap7*/start.sh
mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/shoot.sh

cnt="$(pg9*/sql.sh -t -c "select count(*) from audit_event" mc_test)"
# make sure now it redirects to ap7
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap7*/print_address.sh)
# audit event shouldn't contain recent mirror_probe event, becuase we know that ap7 is not preferable because of recent probe error
test 0 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt" mc_test)
