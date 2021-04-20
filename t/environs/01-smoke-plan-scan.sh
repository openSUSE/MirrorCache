#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

export MIRRORCACHE_PERMANENT_JOBS='folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses'

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


pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us','na'" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','de','eu'" mc_test


export MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=1
export MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=3 # smaller value may be not enough in slow environement
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=mx
mc9*/backstage/shoot.sh
test 1 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'" mc_test)

# pg9*/sql.sh -t -c "select * from minion_locks" mc_test
# sleep 1
pg9*/sql.sh -t -c "select * from minion_locks" mc_test

# request from mx goes to us
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=mx | grep -C10 302 | grep "$(ap7*/print_address.sh)"
mc9*/backstage/shoot.sh
pg9*/sql.sh -t -c "select * from minion_locks" mc_test
# MIRRORCACHE_MIRROR_RESCAN_TIMEOUT hasn't passed yet, so no scanning job should occur
test 1 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'" mc_test)


sleep $MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT
sleep $MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=mx | grep -C10 302 | grep "$(ap7*/print_address.sh)"
mc9*/backstage/shoot.sh
# now another job should start
test 2 == $(pg9*/sql.sh -t -c "select count(*) from minion_jobs where task = 'mirror_scan' and args::varchar like '%/folder1%mx%'" mc_test)
