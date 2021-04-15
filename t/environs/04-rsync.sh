#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

./environ.sh rs9-system2
rs9*/configure_dir.sh dt "$(pwd)"/rs9-system2/dt
rs9*/start.sh
rs9*/status.sh

mc9*/configure_db.sh pg9
export MIRRORCACHE_PEDANTIC=1
export MIRRORCACHE_ROOT=rsync://$USER:$USER@$(rs9*/print_address.sh)/dt
export MIRRORCACHE_REDIRECT=http://some.address.fake.com

./environ.sh ap8-system2
./environ.sh ap7-system2

for x in rs9-system2 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    echo -n 123 > $x/dt/folder1/file2.dat
    $x/start.sh
done

# check rsync module is up properly
rs9*/ls_dt.sh

mc9*/start.sh
mc9*/status.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

# remove folder1/file1.dt from ap8
rm ap8-system2/dt/folder1/file2.dat

# first request redirected to root
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep fake.com

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from file" mc_test
test 0 == $(pg9*/sql.sh -t -c "select size from file where name = 'file1.dat'" mc_test)
test 3 == $(pg9*/sql.sh -t -c "select size from file where name = 'file2.dat'" mc_test)
test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap7*/print_address.sh)

curl -H "Accept: */*, application/metalink+xml" -s http://127.0.0.1:3190/download/folder1/file2.dat | grep '<size>3</size>'

mv ap7-system2/dt/folder1/file2.dat ap8-system2/dt/folder1/
echo -n 123456789 > rs9-system2/dt/folder1/file2.dat

# gets redirected to root again
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep fake.com

# call incorrect file to force new size sync sync
curl -s http://127.0.0.1:3190/download/folder1/incorrect
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule

# ask mirror rescan
mc9*/backstage/job.sh mirror_scan_schedule_from_misses
mc9*/backstage/shoot.sh

# check correct file size in DB
test 9 == $(pg9*/sql.sh -t -c "select max(size) from file where name = 'file2.dat'" mc_test)

# reports correct size in metalink
curl -H "Accept: */*, application/metalink+xml" -s http://127.0.0.1:3190/download/folder1/file2.dat | grep '<size>9</size>'

# still redirects to root because size differs
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep fake.com

# update file on ap8
cp rs9-system2/dt/folder1/file2.dat ap8-system2/dt/folder1/

# now redirects to ap8
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap8*/print_address.sh)


# now add new file everywhere
for x in rs9-system2 ap7-system2 ap8-system2; do
    touch $x/dt/folder1/file3.dat
done

# first request will miss
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat | grep fake.com

# force rescan
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh
# now expect to hit
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat | grep -E "$(ap8*/print_address.sh)|$(ap7*/print_address.sh)"

# now add new file only on main server and make sure it doesn't try to redirect
touch rs9-system2/dt/folder1/file4.dat

curl -Is http://127.0.0.1:3190/download/folder1/file4.dat | grep fake.com
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_server" mc_test)

cnt="$(pg9*/sql.sh -t -c "select count(*) from audit_event" mc_test)"

curl -Is http://127.0.0.1:3190/download/folder1/file4.dat

# it shouldn't try to probe yet, because scanner didn't find files on the mirrors
test 0 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt" mc_test)

for x in rs9-system2 ap7-system2 ap8-system2; do
    mkdir $x/dt/folder1/folder11
    touch $x/dt/folder1/folder11/file1.dat
done

# this is needed for schedule jobs to retry on next shoot
curl -Is http://127.0.0.1:3190/download/folder1/folder11/file1.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/folder11/file1.dat | grep -E '1314|1304'
curl -s http://127.0.0.1:3190/download/folder1/folder11/ | grep file1.dat


curl -s http://127.0.0.1:3190/download/folder1?status=all | grep '"recent":2'| grep '"not_scanned":0' | grep '"outdated":0'
curl -s http://127.0.0.1:3190/download/folder1?status=recent | grep 127.0.0.1:1304 | grep 127.0.0.1:1314
test {} == $(curl -s http://127.0.0.1:3190/download/folder1?status=outdated)
test {} == $(curl -s http://127.0.0.1:3190/download/folder1?status=not_scanned)

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



##################################
# test file with colon ':'
for x in rs9-system2 ap7-system2 ap8-system2; do
    touch $x/dt/folder1/file:4.dat
done

# first request will miss
curl -Is http://127.0.0.1:3190/download/folder1/file:4.dat | grep fake.com

# force rescan
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh
# now expect to hit
curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat
curl -s http://127.0.0.1:3190/download/folder1/ | grep file:4.dat
curl -Is http://127.0.0.1:3190/download/folder1/file:4.dat | grep -E "$(ap8*/print_address.sh)|$(ap7*/print_address.sh)"
##################################


