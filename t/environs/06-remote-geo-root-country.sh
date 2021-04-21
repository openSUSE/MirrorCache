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
export MIRRORCACHE_ROOT_COUNTRY=de
mc9*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1324','/','t','cz',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.4:1324','/','t','cn',''" mc_test


mc9*/backstage/job.sh -e folder_sync -a '["/folder1"]'
mc9*/backstage/job.sh -e mirror_scan -a '["/folder1"]'
mc9*/backstage/shoot.sh

curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=de
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=it
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=cz
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=cn
curl -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=au

# sleep 1
pg9*/sql.sh -c "select * from stat order by id" mc_test
test 5 == $(pg9*/sql.sh -t -c "select count(*) from stat" mc_test)
test 0 == $(pg9*/sql.sh -t -c "select count(*) from stat where country='us'" mc_test)
test 1 == $(pg9*/sql.sh -t -c "select count(*) from stat where mirror_id = -1" mc_test) # only one miss
test 1 == $(pg9*/sql.sh -t -c "select count(*) from stat where country='cz' and mirror_id = 2" mc_test)
test 2 == $(pg9*/sql.sh -t -c "select count(*) from stat where mirror_id = 0" mc_test) # de + it

mc9*/backstage/job.sh stat_agg_schedule
mc9*/backstage/shoot.sh

curl -s http://127.0.0.1:3190/rest/stat
curl -s http://127.0.0.1:3190/rest/stat | grep '"hit":4' | grep '"miss":1'
