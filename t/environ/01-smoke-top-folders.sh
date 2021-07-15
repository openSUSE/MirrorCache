#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
$mc/gen_env "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc/start

$mc/curl -I /folder1/file1.1.dat | grep 404
mkdir $mc/dt/folder1
touch $mc/dt/folder1/file1.1.dat
$mc/curl -I /folder1/file1.1.dat | grep 200
mkdir $mc/dt/folder3
touch $mc/dt/folder3/file1.1.dat
$mc/curl -I /folder3/file1.1.dat | grep 200

$mc/curl -I /folder1//file1.1.dat?COUNTRY=us | grep -i 'Location: /folder1/file1.1.dat?COUNTRY=us'

$mc/curl -i / | grep -C 30 folder1 | grep folder3
