#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/start.sh

pg9*/create.sh db mc_test
./environ.sh ng9-system2
./environ.sh ap9-system2
mc9*/configure_db.sh pg9
export MIRRORCACHE_PEDANTIC=1

# read from nginx and redirect to apache
export MIRRORCACHE_ROOT=http://$(ng9*/print_address.sh)
export MIRRORCACHE_REDIRECT=http://$(ap9*/print_address.sh)
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

# first request redirected to MIRRORCACHE_REDIRECT, eventhough files are not there
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap9*/print_address.sh)

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh


test 2 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from folder_diff_file" mc_test)

curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng7*/print_address.sh)

mv ng7-system2/dt/folder1/file2.dat ng8-system2/dt/folder1/

# gets redirected to MIRRORCACHE_REDIRECT again
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap9*/print_address.sh)

mc9*/backstage/job.sh mirror_scan_schedule_from_misses
mc9*/backstage/shoot.sh

curl -H "Accept: */*, application/metalink+xml" -s http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ap9*/print_address.sh)

# now redirects to ng8
curl -Is http://127.0.0.1:3190/download/folder1/file2.dat | grep $(ng8*/print_address.sh)
