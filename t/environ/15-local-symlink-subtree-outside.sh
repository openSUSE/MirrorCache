#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
$mc/start
$mc/status

mkdir -p $mc/dt/{folder1,folder2}
echo $mc/dt/folder1/file1.1.dat | xargs -n 1 touch

mkdir -p $mc/dt/updates/tool
(
cd $mc/dt/updates/tool/
ln -s ../../folder1 v1
)

ls -la $mc/dt/updates/tool/

# Register the folder in the database by requesting its mirrorlist on the headquarter
$mc/curl -Is /download/updates/tool/v1/file1.1.dat.mirrorlist

mcsub=$mc/sub

$mcsub/gen_env MIRRORCACHE_ROOT="'$mc/dt:testhost.com:testhost.vpn'" \
               MIRRORCACHE_SUBTREE=/updates \
               MIRRORCACHE_TOP_FOLDERS=tool \
               MIRRORCACHE_ROOT_COUNTRY=us

$mcsub/start

# Run folder sync to resolve symlink and populate the file in the database under the real folder
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

# Verify that the file is in the database under folder1 (the real folder)
$mc/sql_test 1 == "select count(*) from file where name = 'file1.1.dat'"

# Now, request from subfolder service
# Since file1.1.dat is now in the database under /folder1/file1.1.dat (which is outside /updates),
# without the fix, RootLocal.pm's render_file will prepend /updates to the path, resulting in:
# Location: http://testhost.com/updates/folder1/file1.1.dat
# With the fix, it should be:
# Location: http://testhost.com/folder1/file1.1.dat

rc=0
$mcsub/curl -I /tool/v1/file1.1.dat | grep 'Location: http://testhost.com/folder1/file1.1.dat' || rc=$?

if [ $rc -ne 0 ]; then
    echo "BUG DETECTED: Redirect location was wrong!"
    # Print what the actual redirect location was
    $mcsub/curl -I /tool/v1/file1.1.dat
    exit 1
else
    echo "SUCCESS: Redirect location was correct!"
fi
