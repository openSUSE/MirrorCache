#!lib/test-in-container-environ.sh

# Smoke test for https-only mirrors
set -ex

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses cleanup stat_agg_schedule'" \
            MOJO_CA_FILE=$(pwd)/ca/ca.pem MOJO_REVERSE_PROXY=1

$mc/start
$mc/status

# main server supports both http and https
ap9=$(environ ap9)
$ap9/configure_add_https

#####################################
# config apache to redirect http and https to mc
echo 'LoadModule proxy_module /usr/lib64/apache2-prefork/mod_proxy.so
LoadModule proxy_http_module /usr/lib64/apache2-prefork/mod_proxy_http.so
LoadModule headers_module /usr/lib64/apache2-prefork/mod_headers.so' > $ap9/extra-proxy.conf

echo 'ProxyPreserveHost On
ProxyPass / http://'$($mc/print_address)'/
ProxyPassReverse / http://'$($mc/print_address)'/
<If "%{HTTPS} == '"'"'on'"'"'>
RequestHeader set X-Forwarded-HTTPS "1"
RequestHeader set X-Forwarded-Proto "https"
</If>
' > $ap9/dir.conf
#####################################

$ap9/start
$ap9/status

$ap9/curl_https / > /dev/null

# this mirror will do only http
ap8=$(environ ap8)
# this mirror will do only https
ap7=$(environ ap7)
$ap7/configure_ssl

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap9/curl_https /download/  | grep folder1
$ap9/curl       /download/  | grep folder1

######

$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/shoot
$mc/sql_test 1 == "select 1 from server_capability_check where server_id=1 and capability='http'"
$mc/sql_test 1 == "select 1 from server_capability_check where server_id=2 and capability='https'"

# now explicitly force disable corresponding capabilities
$mc/db/sql "insert into server_capability_force(server_id,capability,dt) select 1,'http',now()"
$mc/db/sql "insert into server_capability_force(server_id,capability,dt) select 2,'https',now()"

$ap9/curl_https --cacert ca/ca.pem -I /download/folder1/file1.1.dat

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# make sure https redirects to https
$ap9/curl_https -I /download/folder1/file1.1.dat | grep https:// | grep $($ap7/print_address)
$ap9/curl -I /download/folder1/file1.1.dat | grep http:// | grep $($ap8/print_address)
