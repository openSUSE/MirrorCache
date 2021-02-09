#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9
mc9*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','us',''" mc_test

mc9*/curl.sh rest/server | grep 1304 | grep 1314

mc9*/curl.sh rest/myip --interface 127.0.0.3
mc9*/curl.sh rest/myip --interface 127.0.0.3 | grep -C10 -i '\bDE\b' | grep -i '\bEU\b'

