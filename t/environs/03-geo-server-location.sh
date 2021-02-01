#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
./environ.sh mc9 $(pwd)/MirrorCache
pg9*/start.sh
pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test
mc9*/configure_db.sh pg9

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','/','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','/','t','de',''" mc_test 

mc9*/backstage/job.sh -e mirror_location -a [1]
mc9*/backstage/shoot.sh

res=$(pg9*/sql.sh -t -c 'select round(lat,2), round(lng,2) from server where id = 1' mc_test)
test ' 37.75 | -97.82' == "$res"
res=$(pg9*/sql.sh -t -c 'select round(lat,2), round(lng,2) from server where id = 2' mc_test)
test ' 37.75 | -97.82' != "$res"
