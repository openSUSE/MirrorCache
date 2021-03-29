#!lib/test-in-container-environs.sh

# Smoke test for https-only mirrors
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

MOJO_CA_FILE=$(pwd)/ca/ca.pem MOJO_REVERSE_PROXY=1 mc9*/start.sh
mc9*/status.sh

# main server supports both http and https
./environ.sh ap9-system2
ap9*/configure_add_https.sh

#####################################
# config apache to redirect http and https to mc
echo 'LoadModule proxy_module /usr/lib64/apache2-prefork/mod_proxy.so
LoadModule proxy_http_module /usr/lib64/apache2-prefork/mod_proxy_http.so
LoadModule headers_module /usr/lib64/apache2-prefork/mod_headers.so' > ap9-system2/extra-proxy.conf

echo 'ProxyPreserveHost On
ProxyPass / http://127.0.0.1:3190/
ProxyPassReverse / http://127.0.0.1:3190/
<If "%{HTTPS} == '"'"'on'"'"'>
RequestHeader set X-Forwarded-HTTPS "1"
RequestHeader set X-Forwarded-Proto "https"
</If>
' > ap9-system2/dir.conf
#####################################

ap9*/start.sh
ap9*/status.sh

ap9*/curl_https.sh / > /dev/null 

# this mirror will do only http
./environ.sh ap8-system2
# this mirror will do only https
./environ.sh ap7-system2
ap7*/configure_ssl.sh

for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap9*/curl_https.sh /download  | grep folder1

######

ap7*/status.sh >& /dev/null || ap7*/start.sh
ap8*/status.sh >& /dev/null || ap8*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

MOJO_CA_FILE=$(pwd)/ca/ca.pem mc9*/backstage/shoot.sh
test f == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=1 and capability='http'" mc_test)
test t == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=1 and capability='https'" mc_test)
test t == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=2 and capability='http'" mc_test)
test f == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=2 and capability='https'" mc_test)

# now explicitly force disable corresponding capabilities
pg9*/sql.sh -t -c "insert into server_capability_force(server_id,capability,dt) select 1,'http',now();" mc_test
pg9*/sql.sh -t -c "insert into server_capability_force(server_id,capability,dt) select 2,'https',now();" mc_test

curl --cacert ca/ca.pem -I https://127.0.0.1:1524/download/folder1/file1.dat

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
MOJO_CA_FILE=$(pwd)/ca/ca.pem mc9*/backstage/shoot.sh

# make sure https redirects to https
curl --cacert ca/ca.pem -I -s https://127.0.0.1:1524/download/folder1/file1.dat | grep https:// | grep $(ap7*/print_address.sh)
curl -I -s http://127.0.0.1:1324/download/folder1/file1.dat | grep http:// | grep $(ap8*/print_address.sh)
