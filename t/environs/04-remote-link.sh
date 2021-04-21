#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :
./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2

./environ.sh mc9 $(pwd)/MirrorCache

for x in ap7-system2 ap8-system2 ap9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

pg9*/status.sh 2 > /dev/null || {
    pg9*/start.sh
    pg9*/create.sh db mc_test
    ln -s $(pwd)/ap9-system2/dt/folder1 $(pwd)/ap9-system2/dt/link
echo '    RewriteEngine On
    RewriteBase "/"
    RewriteRule ^link(/.*)?$ folder1$1 [R]
' > ap9-system2/directory-rewrite.conf

echo 'LoadModule rewrite_module    /usr/lib64/apache2-prefork/mod_rewrite.so' > ap9-system2/extra-rewrite.conf
}

mc9*/configure_db.sh pg9
export MIRRORCACHE_ROOT=http://$(ap9*/print_address.sh)

for x in ap7-system2 ap8-system2 ap9-system2; do
    $x/start.sh
done

# make sure rewrite works properly in apache
curl -I $(ap9*/print_address.sh)/link | grep -A3 302 | grep folder1

mc9*/start.sh
mc9*/status.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','/','t','us',''" mc_test
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1314','/','t','us',''" mc_test

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/start.sh

################################################
# Test symlinks

curl -Is http://127.0.0.1:3190/download/link
curl -Is http://127.0.0.1:3190/download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
################################################

# make sure symlinks still work after further folder_sync_schedule_from_misses
sleep 10
curl -Is http://127.0.0.1:3190/download/link
curl -Is http://127.0.0.1:3190/download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
sleep 10
curl -Is http://127.0.0.1:3190/download/link
curl -Is http://127.0.0.1:3190/download/link | grep -A4 -E '301|302' | grep ': /download/folder1'
