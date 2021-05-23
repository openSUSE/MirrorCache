#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
$mc/gen_env "MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'"
$mc/start

$mc/curl -I /folder1/file1.dat | grep 'Location: /download/folder1/file1.dat'
$mc/curl -I /folder3/file1.dat | grep 'Location: /download/folder3/file1.dat'

$mc/curl -I /folder1/file1.dat?COUNTRY=us | grep 'Location: /download/folder1/file1.dat?COUNTRY=us'
