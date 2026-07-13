#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start
$mc/status

# Create folder1 and a symlink pointing to '.' inside it
mkdir -p $mc/dt/folder1
echo "hello" > $mc/dt/folder1/file1.txt
(
cd $mc/dt/folder1
ln -s . Changes
)

# Sync folder1
$mc/backstage/job -e folder_sync -a '["/folder1", 1]'
$mc/backstage/shoot

# Check if a redirect was inserted for /folder1/Changes -> /folder1
$mc/sql_test 1 == "select count(*) from redirect where pathfrom = '/folder1/Changes' and pathto = '/folder1'"

# Check that NO nested redirects like /folder1/Changes/Changes exist
$mc/sql_test 0 == "select count(*) from redirect where pathfrom like '%Changes/Changes%'"

echo success
