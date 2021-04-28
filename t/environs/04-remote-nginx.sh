#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/start.sh

pg9*/create.sh db mc_test
./environ.sh ng9-system2
mc9*/configure_db.sh pg9
export MIRRORCACHE_PEDANTIC=1
export MIRRORCACHE_ROOT=http://$(ng9*/print_address.sh)
export MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

./environ.sh ng8-system2
./environ.sh ng7-system2

for x in ng7-system2 ng8-system2 ng9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    echo -n 0123456789 > $x/dt/folder1/file2.dat
    $x/start.sh
done

mc9*/start.sh
mc9*/status.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '$(ng7*/print_address.sh)','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '$(ng8*/print_address.sh)','','t','us',''" mc_test

# remove folder1/file1.dt from ng8
rm ng8-system2/dt/folder1/file2.dat

# first request redirected to root
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng9*/print_address.sh)

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from file" mc_test
test 0  == $(pg9*/sql.sh -t -c "select size from file where name='file1.dat'" mc_test)
test 10 == $(pg9*/sql.sh -t -c "select size from file where name='file2.dat'" mc_test)


test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng7*/print_address.sh)

mv ng7-system2/dt/folder1/file2.dat ng8-system2/dt/folder1/

# gets redirected to root again
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng9*/print_address.sh)

mc9*/backstage/job.sh mirror_scan_schedule_from_misses
mc9*/backstage/shoot.sh

curl -H "Accept: */*, application/metalink+xml" -s http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng9*/print_address.sh)

# now redirects to ng8
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng8*/print_address.sh)

# now add new file everywhere
for x in ng9-system2 ng7-system2 ng8-system2; do
    touch $x/dt/folder1/file3.dat
done


# force rescan
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh
# now expect to hit
curl -Is http://127.0.0.1:3190/download/folder1/file3.dat | grep -E "$(ng8*/print_address.sh)|$(ng7*/print_address.sh)"

# now add new file only on main server and make sure it doesn't try to redirect
touch ng9-system2/dt/folder1/file4.dat

curl -Is http://127.0.0.1:3190/download/folder1/file4.dat | grep -E "$(ng9*/print_address.sh)"
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_server" mc_test)

cnt="$(pg9*/sql.sh -t -c "select count(*) from audit_event" mc_test)"

curl -Is http://127.0.0.1:3190/download/folder1/file4.dat

# it shouldn't try to probe yet, because scanner didn't find files on the mirrors
test 0 == $(pg9*/sql.sh -t -c "select count(*) from audit_event where name = 'mirror_probe' and id > $cnt" mc_test)

for x in ng9-system2 ng7-system2 ng8-system2; do
    mkdir $x/dt/folder1/folder11
    touch $x/dt/folder1/folder11/file1.dat
done

# this is needed for schedule jobs to retry on next shoot
curl -Is http://127.0.0.1:3190/download/folder1/folder11/file1.dat
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/folder11/file1.dat | grep -E "$(ng7*/print_address.sh)|$(gn8*/print_address.sh)"
curl -s http://127.0.0.1:3190/download/folder1/folder11/ | grep file1.dat


curl -s http://127.0.0.1:3190/download/folder1?status=all | grep '"recent":2'| grep '"not_scanned":0' | grep '"outdated":0'
curl -s http://127.0.0.1:3190/download/folder1?status=recent | grep $(ng7*/print_address.sh) | grep $(ng7*/print_address.sh)
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
for x in ng9-system2 ng7-system2 ng8-system2; do
    touch $x/dt/folder1/file:4.dat
done

# first request will miss
curl -Is http://127.0.0.1:3190/download/folder1/file:4.dat | grep -E "$(ng9*/print_address.sh)"


pg9*/sql.sh  -c "select s.id, s.hostname, fd.id, fd.hash, fl.name, fd.dt, fl.dt
from
folder_diff fd
join folder_diff_server fds on fd.id = fds.folder_diff_id
join server s on s.id = fds.server_id
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fdf.file_id = fl.id
left join folder f on fd.folder_id = f.id
order by f.id, s.id, fl.name
" mc_test

# force rescan
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh  -c "select s.id, s.hostname, fd.id, fd.hash, fl.name, fd.dt, fl.dt
from
folder_diff fd
join folder_diff_server fds on fd.id = fds.folder_diff_id
join server s on s.id = fds.server_id
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fdf.file_id = fl.id
left join folder f on fd.folder_id = f.id
order by f.id, s.id, fl.name
" mc_test

# now expect to hit
curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat
curl -s http://127.0.0.1:3190/download/folder1/ | grep file:4.dat
curl -Is http://127.0.0.1:3190/download/folder1/file:4.dat | grep -E "$(ng8*/print_address.sh)|$(ng7*/print_address.sh)"
##################################

f=0123456789012345678901234567890123456789.\(\#@~\)abcdefghijklmnoprst.dat

for x in ng7-system2 ng8-system2 ng9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo -n 0123456789 > $x/dt/folder1/$f
done


mc9*/backstage/job.sh -e folder_sync -a "['/folder1']"
mc9*/backstage/shoot.sh

mc9*/curl.sh download/folder1/ | grep -A1 $f | grep '10 Byte'
