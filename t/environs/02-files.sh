#!lib/test-in-container-environs.sh
set -exo pipefail

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -v ON_ERROR_STOP=1 -f $(pwd)/MirrorCache/sql/schema.sql mc_test

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
ap8*/status.sh >& /dev/null || ap8*/start.sh


pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

# remove folder1/file1.dt from ap8
rm ap8-system2/dt/folder1/file2.dat

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from file" mc_test
test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep 302

mv ap7-system2/dt/folder1/file2.dat ap8-system2/dt/folder1/

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat?PEDANTIC=0 | grep 302
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat?PEDANTIC=1 | grep 200

mc9*/backstage/job.sh mirror_scan_schedule_from_misses
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep 302
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 302

# now add new file everywhere
for x in mc9 ap7-system2 ap8-system2; do
    touch $x/dt/folder1/file3.dat
done

# first request will miss
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat | grep 200

# force rescan
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh
# now expect to hit
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat | grep 302

# now add new file only on main server and make sure it doesn't try to redirect
touch mc9/dt/folder2/file4.dat

curl -Is http://127.0.0.1:3190/download/folder2/file4.dat | grep 200
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

test 4 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_server" mc_test)

cnt="$(pg9*/sql.sh -t -c "select count(*) from audit_event" mc_test)"

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep 302

# it shouldn't try to reach file on mirrors yet, because scanner didn't find files
test 0 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name like 'mirror_miss' and id > $cnt" mc_test)


curl -Is http://127.0.0.1:3190/download/folder2/file4.dat | grep 200
# now an error must be logged
test 1 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name like 'mirror_miss' and id > $cnt" mc_test)

##################################
# let's test path distortions
# remember number of folders in DB
cnt=$(pg9*/sql.sh -t -c "select count(*) from folder" mc_test)
curl -Is http://127.0.0.1:3190/download//folder1//file1.dat
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh
test $cnt == $(pg9*/sql.sh -t -c "select count(*) from folder" mc_test)

curl -Is http://127.0.0.1:3190/download//folder1//file1.dat              | grep -C 10 -P '[^/]/folder1/file1.dat' | grep 302
curl -Is http://127.0.0.1:3190/download//folder1///file1.dat             | grep -C 10 -P '[^/]/folder1/file1.dat' | grep 302
curl -Is http://127.0.0.1:3190/download/./folder1/././file1.dat          | grep -C 10 -P '[^/]/folder1/file1.dat' | grep 302
curl -Is http://127.0.0.1:3190/download/./folder1/../folder1/./file1.dat | grep -C 10 -P '[^/]/folder1/file1.dat' | grep 302
##################################

# now add media.1/media
for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/folder1/media.1
    echo CONTENT1 > $x/dt/folder1/media.1/file1.dat
    echo CONTENT2 > $x/dt/folder1/media.1/media
done

curl -Is http://127.0.0.1:3190/download/folder1/media.1/media

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

curl -is http://127.0.0.1:3190/download/folder1/media.1/file1.dat.metalink | grep location
curl -is -H 'Accept: */*, application/metalink+xml' http://127.0.0.1:3190/download/folder1/media.1/file1.dat| grep location

test -z "$(curl -is -H 'Accept: */*, application/metalink+xml' http://127.0.0.1:3190/download/folder1/media.1/media | grep location)" || FAIL media.1/media must not return metalink
curl -is http://127.0.0.1:3190/download/folder1/media.1/media.metalink | grep location
curl -iLs -H 'Accept: */*, application/metalink+xml' http://127.0.0.1:3190/download/folder1/media.1/media | grep CONTENT2
