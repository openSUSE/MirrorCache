#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start
$mc/status

mkdir -p $mc/dt/{folder1,folder2,folder3}
echo $mc/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch

# local root can just show files without scanning
$mc/curl /download/folder1/ | grep file1.1.dat

$mc/curl /download/folder1/?JSON | grep '"name":"file1.1.dat","size":0' | grep '"name":"file2.1.dat","size":0}'
