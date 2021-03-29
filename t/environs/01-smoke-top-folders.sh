#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

MIRRORCACHE_TOP_FOLDERS="folder1 folder2 folder3" mc9*/start.sh
mc9*/status.sh

curl -Is http://127.0.0.1:3190/folder1/file1.dat | grep 'Location: /download/folder1/file1.dat'
curl -Is http://127.0.0.1:3190/folder3/file1.dat | grep 'Location: /download/folder3/file1.dat'

curl -Is http://127.0.0.1:3190/folder1/file1.dat?COUNTRY=us | grep 'Location: /download/folder1/file1.dat?COUNTRY=us'
