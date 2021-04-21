#!lib/test-in-container-environs.sh
set -ex

# environ by number:
# 9  headquarter 
# 6 -NA subsidiary 
# 7 - EU subsidiary 
# 8- ASIA subsidiary 

for i in 6 7 8 9; do
    ./environ.sh pg$i-system2
    ./environ.sh mc$i $(pwd)/MirrorCache
    pg$i*/start.sh
    pg$i*/create.sh db mc_test
    mc$i*/configure_db.sh pg$i
    mkdir -p mc$i/dt/{folder1,folder2,folder3}
    echo mc$i/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

hq_address=$(mc9*/print_address.sh)
na_address=$(mc6*/print_address.sh)
na_interface=127.0.0.2
eu_address=$(mc7*/print_address.sh)
eu_interface=127.0.0.3
as_address=$(mc8*/print_address.sh)
as_interface=127.0.0.4

# deploy db
mc9*/backstage/shoot.sh

pg9*/sql.sh -c "insert into subsidiary(hostname,region) select '$na_address','na'" mc_test
pg9*/sql.sh -c "insert into subsidiary(hostname,region) select '$eu_address','eu'" mc_test
pg9*/sql.sh -c "insert into subsidiary(hostname,region) select '$as_address','as'" mc_test

mc9*/start.sh
MIRRORCACHE_REGION=na MIRRORCACHE_HEADQUARTER=$hq_address mc6*/start.sh
MIRRORCACHE_REGION=eu MIRRORCACHE_HEADQUARTER=$hq_address mc7*/start.sh
MIRRORCACHE_REGION=as MIRRORCACHE_HEADQUARTER=$hq_address mc8*/start.sh



curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.dat | grep "Location: http://$na_address/download/folder1/file1.dat"
curl --interface $eu_interface -Is http://$hq_address/download/folder1/file1.dat | grep "Location: http://$eu_address/download/folder1/file1.dat"
curl --interface $as_interface -Is http://$hq_address/download/folder1/file1.dat | grep "Location: http://$as_address/download/folder1/file1.dat"

curl --interface $na_interface -Is http://$na_address/download/folder1/file1.dat | grep '200 OK'
curl --interface $eu_interface -Is http://$na_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $as_interface -Is http://$na_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"

curl --interface $na_interface -Is http://$eu_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $eu_interface -Is http://$eu_address/download/folder1/file1.dat | grep '200 OK'
curl --interface $as_interface -Is http://$eu_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"

curl --interface $na_interface -Is http://$as_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $eu_interface -Is http://$as_address/download/folder1/file1.dat | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.dat | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.dat?COUNTRY=us | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.dat?COUNTRY=cn | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.dat?REGION=na | grep "Location: http://$hq_address/download/folder1/file1.dat"
curl --interface $as_interface -Is "http://$as_address/download/folder1/file1.dat?COUNTRY=cn&REGION=na" | grep "Location: http://$hq_address/download/folder1/file1.dat"

# check non-download routers shouldn't be redirected
curl --interface $na_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/rest/server | grep '200 OK'
curl --interface $na_interface -Is http://$na_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$eu_address/rest/server | grep '200 OK'
