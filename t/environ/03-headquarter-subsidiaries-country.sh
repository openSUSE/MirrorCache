#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 6 - NA subsidiary
# 7 - EU subsidiary
# 8 - Japan subsidiary

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
cn_address=$($mc8/print_address)
cn_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'
$mc9/backstage/shoot

$mc9/db/sql "insert into subsidiary(hostname,region) select '$na_address','na'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/db/sql "insert into subsidiary(hostname,region) select '$cn_address','cn'"

$mc9/start
$mc6/gen_env MIRRORCACHE_REGION=na
$mc6/start
$mc7/gen_env MIRRORCACHE_REGION=eu
$mc7/start
$mc8/gen_env MIRRORCACHE_REGION=cn
$mc8/start

echo the root folder is not redirected
curl --interface $eu_interface -Is http://$hq_address/ | grep '200 OK'

echo check redirection from headquarter
curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$na_address/download/folder1/file1.1.dat"
curl --interface $eu_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$eu_address/download/folder1/file1.1.dat"
curl --interface $cn_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep "Location: http://$cn_address/download/folder1/file1.1.dat"

curl -si --interface $eu_interface http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>$eu_address</host>"
curl -si --interface $cn_interface http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>$cn_address</host>"

echo check redirection from na
curl --interface $na_interface -Is http://$na_address/download/folder1/file1.1.dat | grep '200 OK'
curl --interface $eu_interface -Is http://$na_address/download/folder1/file1.1.dat | grep '200 OK'

echo check redirection from eu
curl --interface $eu_interface -Is http://$eu_address/download/folder1/file1.1.dat | grep '200 OK'

echo check redirection from cn
curl --interface $cn_interface -Is http://$cn_address/download/folder1/file1.1.dat | grep '200 OK'
curl --interface $cn_interface -Is http://$cn_address/download/folder1/file1.1.dat?COUNTRY=cn | grep '200 OK'

echo check non-download routers shouldnt be redirected
curl --interface $na_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $cn_interface -Is http://$hq_address/rest/server | grep '200 OK'
curl --interface $cn_interface -Is http://$cn_address/rest/server | grep '200 OK'
curl --interface $na_interface -Is http://$na_address/rest/server | grep '200 OK'
curl --interface $eu_interface -Is http://$eu_address/rest/server | grep '200 OK'

$mc9/stop
echo "export MIRRORCACHE_INI=$mc9/conf.ini" >> $mc9/conf.env
echo "export MIRRORCACHE_GEOIP_EU=test1.com" >> $mc9/conf.env
echo "geoip_as=test2.com" >> $mc9/conf.ini
$mc9/start

curl -si --interface $eu_interface http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>test1.com</host>"
curl -si --interface $cn_interface http://$hq_address/geoip     | grep -A 50 '200 OK' | grep "<host>test2.com</host>"

echo success
