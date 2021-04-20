#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

for x in ap6-system2 ap7-system2 ap8-system2 ap9-system2; do
    ./environ.sh $x
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start.sh
done

export MIRRORCACHE_ROOT=http://$(ap6*/print_address.sh)
export MIRRORCACHE_STAT_FLUSH_COUNT=1
export MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3

mc9*/start.sh
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','/','t','de',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.4:1324','/','t','cn',''" mc_test

curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat

test 0 == "$(grep -c Poll mc9/.cerr)"

sleep 10
mc9*/backstage/job.sh -e mirror_scan -a '["/folder1","cn"]'

# check redirects to headquarter are logged properly
pg9*/sql.sh -c "select * from stat" mc_test
test -1 == $(pg9*/sql.sh -t -c "select mirror_id from stat where country='us'" mc_test)
test -1 == $(pg9*/sql.sh -t -c "select distinct mirror_id from stat where country='de'" mc_test)
test -z $(pg9*/sql.sh -t -c "select mirror_id from stat where country='cn'" mc_test)

curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1324
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1314
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1304

pg9*/sql.sh -c "select * from stat" mc_test
# check stats are logged properly
test 2 == $(pg9*/sql.sh -t -c "select distinct mirror_id from stat where country='de' and mirror_id > 0" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from stat where country='de' and mirror_id > 0" mc_test)

test 3 == $(pg9*/sql.sh -t -c "select distinct mirror_id from stat where country='cn' and mirror_id > 0" mc_test)
test 2 == $(pg9*/sql.sh -t -c "select count(*) from stat where country='cn' and mirror_id > 0" mc_test)

test 1 == $(pg9*/sql.sh -t -c "select distinct mirror_id from stat where country='us' and mirror_id > 0" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from stat where country='us' and mirror_id > 0" mc_test)

test 0 == "$(grep -c Poll mc9/.cerr)"

curl -s http://127.0.0.1:3190/rest/stat
curl -s http://127.0.0.1:3190/rest/stat | grep '"hit":4' | grep '"miss":2'

# now test stat_agg job by injecting some values into yesterday
mc9*/backstage/stop.sh
pg9*/sql.sh -c "insert into stat(path, dt, mirror_id, secure, ipv4, metalink, head) select '/ttt', now() - interval '1 day', mirror_id, 'f', 'f', 'f', 't' from stat" mc_test
pg9*/sql.sh -c "delete from minion_locks where name like 'stat_agg_schedule%'" mc_test
mc9*/backstage/job.sh stat_agg_schedule
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "select * from stat_agg" mc_test
test 4 == $(pg9*/sql.sh -t -c "select count(*) from stat_agg where period = 'day'" mc_test)

curl -s http://127.0.0.1:3190/rest/stat
curl -s http://127.0.0.1:3190/rest/stat | grep '"hit":4' | grep '"miss":2' | grep '"prev_hit":4' | grep '"prev_miss":2'


test 0 == $(pg9*/sql.sh -t -c "select sum(case when head then 0 else 1 end) from stat" mc_test)
curl --interface 127.0.0.2 -is http://127.0.0.1:3190/download/folder1/file1.dat
test 1 == $(pg9*/sql.sh -t -c "select sum(case when head then 0 else 1 end) from stat" mc_test)

test 0 == $(pg9*/sql.sh -t -c "select sum(case when metalink then 1 else 0 end) from stat" mc_test)
curl --interface 127.0.0.2 -Is -H 'Accept: */*, application/metalink+xml' http://127.0.0.1:3190/download/folder1/file1.dat
test 1 == $(pg9*/sql.sh -t -c "select sum(case when metalink then 1 else 0 end) from stat" mc_test)
