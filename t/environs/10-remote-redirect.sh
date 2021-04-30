#!lib/test-in-container-environs.sh

# Smoke test for https-only mirrors
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
# this will be proxy server which redirects https and http to mirrorcache
./environ.sh ap9-system2

./environ.sh ap5-system2
export MIRRORCACHE_ROOT=http://$(ap5*/print_address.sh)
ap5-system2/start.sh

# here we redirect https requests as specified in MIRRORCACHE_FALLBACK_HTTPS_REDIRECT
./environ.sh ap4-system2
export MIRRORCACHE_REDIRECT=$(ap4*/print_address.sh)
ap4-system2/start.sh

mc9*/configure_db.sh pg9

MOJO_CA_FILE=$(pwd)/ca/ca.pem MOJO_REVERSE_PROXY=1 mc9*/start.sh
mc9*/status.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','','t','us',''" mc_test

pg9*/sql.sh -c "insert into server_capability_force select 1, 'http'" mc_test

# main server supports both http and https
./environ.sh ap9-system2
ap9*/configure_add_https.sh

#####################################
# config apache to redirect http and https to mc
echo 'LoadModule proxy_module /usr/lib64/apache2-prefork/mod_proxy.so
LoadModule proxy_http_module /usr/lib64/apache2-prefork/mod_proxy_http.so
LoadModule headers_module /usr/lib64/apache2-prefork/mod_headers.so' > ap9-system2/extra-proxy.conf

echo 'ProxyPreserveHost On
ProxyPass / http://127.0.0.1:3190/download/
ProxyPassReverse / http://127.0.0.1:3190/download/
<If "%{HTTPS} == '"'"'on'"'"'>
RequestHeader set X-Forwarded-HTTPS "1"
RequestHeader set X-Forwarded-Proto "https"
</If>
' > ap9-system2/dir.conf
#####################################

ap9*/start.sh
ap9*/status.sh

# this mirror will do only http
./environ.sh ap8-system2
# this mirror will do only https
./environ.sh ap7-system2
ap7*/configure_ssl.sh

for x in ap7-system2 ap8-system2 ap5-system2 ap4-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap7*/start.sh
ap8*/start.sh

mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
MOJO_CA_FILE=$(pwd)/ca/ca.pem mc9*/backstage/shoot.sh
MOJO_CA_FILE=$(pwd)/ca/ca.pem mc9*/backstage/start.sh

n=0
until curl -s -k http://$(ap9*/print_address.sh)/  | grep folder1 ; do
    sleep 1;
    n=$((n+1))
    test $n -le 10 || ( exit 1 )
done

# the same request as above, just over https
curl -s -k https://127.0.0.1:1524/ | grep folder1

######

n=0
until curl --cacert ca/ca.pem -Is https://127.0.0.1:1524/folder1/file1.dat ; do
    sleep 1;
    n=$((n+1))
    test $n -le 10 || break
done

# make sure https redirects to https
sleep 15
curl --cacert ca/ca.pem -I -s https://127.0.0.1:1524/folder1/file1.dat | grep https:// | grep $(ap7*/print_address.sh)

# shutdown ap7, then https must redirect to ap4
ap7*/stop.sh
curl --cacert ca/ca.pem -I -s https://127.0.0.1:1524/folder1/file1.dat?PEDANTIC=1 | grep https:// | grep $(ap4*/print_address.sh)
