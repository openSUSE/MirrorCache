#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \
    MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT=0

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ln -s $ap9/dt/folder1 $ap9/dt/link
echo '    RewriteEngine On
    RewriteBase "/"
    RewriteRule ^link(/.*)?$ folder1$1 [R]
' > $ap9/directory-rewrite.conf

echo 'LoadModule rewrite_module    /usr/lib64/apache2-prefork/mod_rewrite.so' > $ap9/extra-rewrite.conf

for x in $ap7 $ap8 $ap9; do
    $x/start
done

# make sure rewrite works properly in apache
$ap9/curl -I /link | grep -A3 302 | grep folder1

$mc/start
$mc/status

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

################################################
# Test symlinks

$mc/curl -I /download/link
$mc/curl -I /download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
################################################

# make sure symlinks still work after further folder_sync_schedule_from_misses
sleep 10
$mc/curl -I /download/link
$mc/curl -I /download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
sleep 10
$mc/curl -I /download/link
$mc/curl -I /download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
