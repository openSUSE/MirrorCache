#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary
# 8 - ASIA subsidiary

for i in 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    eval mc$i=$x
done

hq_address=$($mc9/print_address)
na_address=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'
$mc9/backstage/shoot

$mc9/db/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$as_address','as'"

$mc9/start
$mc6/gen_env MIRRORCACHE_REGION=na
$mc6/start
$mc7/gen_env MIRRORCACHE_REGION=eu
$mc7/start
$mc8/gen_env MIRRORCACHE_REGION=as
$mc8/start

echo the root folder is not redirected
curl --interface $eu_interface -Is http://$hq_address/ | grep '200 OK'

echo check redirection from headquarter
curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$na_address/download/folder1/file1.1.dat"
curl --interface $eu_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$eu_address/download/folder1/file1.1.dat"
curl --interface $as_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$as_address/download/folder1/file1.1.dat"

echo check redirection from na
curl --interface $na_interface -Is http://$na_address/download/folder1/file1.1.dat | grep '200 OK'
curl --interface $eu_interface -Is http://$na_address/download/folder1/file1.1.dat | grep '200 OK'

echo check redirection from eu
curl --interface $eu_interface -Is http://$eu_address/download/folder1/file1.1.dat | grep '200 OK'

echo check redirection from as
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.1.dat | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/download/folder1/file1.1.dat?COUNTRY=cn | grep '200 OK'

echo check non-download routers shouldnt be redirected
curl --interface $na_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $as_interface -Is http://$as_address/rest/server | grep '200 OK'
curl --interface $na_interface -Is http://$na_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$eu_address/rest/server | grep '200 OK'
