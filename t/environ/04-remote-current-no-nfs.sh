#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)

$mc/gen_env \
    MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0 \
    MIRRORCACHE_ROOT=http://$($ap9/print_address) \

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}-Media.iso | xargs -n 1 touch
    sha256sum $x/dt/folder1/file1.1-Media.iso > $x/dt/folder1/file1.1-Media.iso.sha256
    echo 111112 > $x/dt/folder1/file2.1-Media.iso
    sha256sum $x/dt/folder1/file2.1-Media.iso > $x/dt/folder1/file2.1-Media.iso.sha256
    ( cd $x/dt/folder1 && ln -s file1.1-Media.iso file-Media.iso && ln -s file1.1-Media.iso.sha256 file-Media.iso.sha256 )
done

echo '    RewriteEngine On
    RewriteBase "/"
    RewriteRule ^folder1/file-Media.iso(.*)?$ folder1/file1.1-Media.iso$1 [R]
' > $ap9/directory-rewrite.conf

echo 'LoadModule rewrite_module    /usr/lib64/apache2-prefork/mod_rewrite.so' > $ap9/extra-rewrite.conf

for x in $ap7 $ap8 $ap9; do
    $x/start
done

$mc/start
$mc/status

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot


$mc/sql "select * from file"

################################################
# Test unversioned Media.iso is redirected to file which is metioned inside corresponding Media.iso.sha256
$mc/curl -I /download/folder1/file-Media.iso        | grep -C 10 302 | grep /download/folder1/file1.1-Media.iso
$mc/curl -I /download/folder1/file-Media.iso.sha256 | grep -C 10 302 | grep /download/folder1/file1.1-Media.iso.sha256
$mc/curl -L /download/folder1/file-Media.iso.sha256 | grep -q "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  "

echo now change the symlink and make sure redirect changes
echo '    RewriteEngine On
    RewriteBase "/"
    RewriteRule ^folder1/file-Media.iso(.*)?$ folder1/file2.1-Media.iso$1 [R]
' > $ap9/directory-rewrite.conf

$ap9/stop
$ap9/start

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot
$mc/curl -I /download/folder1/file-Media.iso        | grep -C 10 302 | grep /download/folder1/file2.1-Media.iso
$mc/curl -I /download/folder1/file-Media.iso.sha256 | grep -C 10 302 | grep /download/folder1/file2.1-Media.iso.sha256
$mc/curl -L /download/folder1/file-Media.iso.sha256 | grep -q "2019dd7afaf5759c68cec4d0e7553227657f01c69da168489116a1c48e40270e  "

echo success

