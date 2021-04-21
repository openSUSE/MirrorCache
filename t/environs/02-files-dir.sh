#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

mc9*/start.sh
mc9*/status.sh

mkdir -p mc9/dt/{folder1,folder2,folder3}
echo mc9/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch

# local root can just show files without scanning
curl -s http://127.0.0.1:3190/download/folder1/ | grep file1.dat

