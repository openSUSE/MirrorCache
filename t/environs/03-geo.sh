#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2

export MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0
for x in mc9 ap7-system2 ap8-system2 ap9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start.sh
done

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us','na'" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','/','t','de','eu'" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.4:1324','/','t','cn','as'" mc_test

curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 200
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1324
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1314
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 1304

# check same continent
curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=jp | grep 1324
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=jp | grep 1324
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=jp | grep 1324

curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=it | grep 1314
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=it | grep 1314
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=it | grep 1314

curl --interface 127.0.0.4 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=ca | grep 1304
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=ca | grep 1304
curl --interface 127.0.0.2 -Is http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=ca | grep 1304

# Further we test that servers are listed only once in metalink output
curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat

duplicates=$(curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat | grep location | grep -E -o 'https?[^"s][^\<]*' | sort | uniq -cd | wc -l)
test 0 == "$duplicates"

curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat | grep -B20 127.0.0.2 |  grep -i 'this country (us)'

# test get parameter COUNTRY
curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=DE | grep -B20 127.0.0.3 | grep -i 'this country (de)'

# test get parameter AVOID_COUNTRY
curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat?AVOID_COUNTRY=DE,US | grep 127.0.0.4

# check continent
curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s http://127.0.0.1:3190/download/folder1/file1.dat?COUNTRY=fr | grep -B20 127.0.0.3
