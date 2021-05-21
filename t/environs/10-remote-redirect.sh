#!lib/test-in-container-environ.sh

# Smoke test for https-only mirrors
set -euxo pipefail

mc=$(environ mc $(pwd))

# this is root from where mirrorcache reads lists of files
ap5=$(environ ap5)
$ap5/start
# here we redirect when no mirror is found as specified in MIRRORCACHE_REDIRECT
ap4=$(environ ap4)
$ap4/start

# this mirror will do only http
ap8=$(environ ap8)
# this mirror will do only https
ap7=$(environ ap7)
$ap7/configure_ssl

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=http://$($ap5/print_address) \
    MIRRORCACHE_REDIRECT=$($ap4/print_address) \
    MOJO_CA_FILE=$(pwd)/ca/ca.pem \
    MOJO_REVERSE_PROXY=1 \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=3 \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us',''"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us',''"

$mc/db/sql -c "insert into server_capability_force select 1, 'http'" mc_test

# main server supports both http and https
ap9=$(environ ap9)
$ap9/configure_add_https

#####################################
# config apache to redirect http and https to mc
echo 'LoadModule proxy_module /usr/lib64/apache2-prefork/mod_proxy.so
LoadModule proxy_http_module /usr/lib64/apache2-prefork/mod_proxy_http.so
LoadModule headers_module /usr/lib64/apache2-prefork/mod_headers.so' > $ap9/extra-proxy.conf

echo 'ProxyPreserveHost On
ProxyPass / http://'$($mc/print_address)'/download/
ProxyPassReverse / http://'$($mc/print_address)'/download/
<If "%{HTTPS} == '"'"'on'"'"'>
RequestHeader set X-Forwarded-HTTPS "1"
RequestHeader set X-Forwarded-Proto "https"
</If>
' > $ap9/dir.conf
#####################################

$ap9/start
$ap9/status

for x in $ap7 $ap8 $ap5 $ap4; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

$ap7/start
$ap8/start

$mc/backstage/job -e mirror_probe -a '["us"]'
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/start

n=0
until curl -s -k http://$($ap9/print_address)/  | grep folder1 ; do
    sleep 1
    n=$((n+1))
    test $n -le 10 || ( exit 1 )
done

# the same request as above, just over https
$ap9/curl_https / | grep folder1

######

n=0
while : ; do
    rc=0
    $ap9/curl_https -IL /folder1/file1.dat | grep "200 OK" || rc=$?
    test $rc != 0 || break
    sleep 1;
    n=$((n+1))
    test $n -le 10 || break
done

$ap9/curl_https -IL /folder1/file1.dat | grep -C30 "200 OK"
$ap9/curl_https -IL /folder1/file1.dat | grep -C30 "200 OK" | grep https:// | grep $($ap7/print_address)


# make sure https redirects to https
sleep 15
# $ap4/curl_https --cacert ca/ca.pem -I -s https://127.0.0.1:1524/folder1/file1.dat | grep https:// | grep $($ap7/print_address)
$ap9/curl_https -I /folder1/file1.dat | grep https:// | grep $($ap7/print_address)

# shutdown ap7, then https must redirect to ap4
$ap7/stop
$ap9/curl_https -I /folder1/file1.dat?PEDANTIC=1 | grep https:// | grep $($ap4/print_address)
