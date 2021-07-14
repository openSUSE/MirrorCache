#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

MIRRORCACHE_TEST_TRUST_AUTH=1 $mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','na'"

# remove folder1/file1.1.dt from ap8
rm $ap8/dt/folder1/file2.1.dat

$mc/curl -I /download/folder1/file2.1.dat
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/db/sql "select * from file"
test 2 == $($mc/db/sql "select count(*) from folder_diff")
test 1 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -X DELETE -I /admin/folder_diff/1

test 1 == $($mc/db/sql "select count(*) from folder")
test 0 == $($mc/db/sql "select count(*) from folder_diff")
test 0 == $($mc/db/sql "select count(*) from folder_diff_file")

$mc/curl -X DELETE -I /admin/folder/1

test 0 == $($mc/db/sql "select count(*) from file")
test 0 == $($mc/db/sql "select count(*) from folder")

######################################################################
# test automated database cleanup for folders that don't exist anymore
# create some entries in table folder
$mc/curl -I /download/folder1/file1.1.dat
$mc/curl -I /download/folder2/file1.1.dat
$mc/curl -I /download/folder3/file1.1.dat
# force rescan
$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

test 3 == $($mc/db/sql "select count(*) from folder")

rm -r $mc/dt/folder1
rm -r $mc/dt/folder2

# this is only for tests - the folder will be deleted only when
export MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT=5

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/job -e folder_sync -a '["/folder2"]'
$mc/backstage/job -e folder_sync -a '["/folder3"]'
$mc/backstage/shoot

# all folders must exist still
test 1 == $($mc/db/sql "select sum(case when path='/folder1' then 1 else 0 end) from folder")
test 1 == $($mc/db/sql "select sum(case when path='/folder2' then 1 else 0 end) from folder")
test 1 == $($mc/db/sql "select sum(case when path='/folder3' then 1 else 0 end) from folder")

$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot

sleep $MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT
$mc/backstage/job -e folder_sync -a '["/folder2"]'
$mc/backstage/job -e folder_sync -a '["/folder3"]'
$mc/backstage/shoot

$mc/db/sql "select * from minion_jobs where task = 'folder_sync'"

# folder1 is not removed yet because its failures were recorded too fast and MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT must be honored
test 1 == $($mc/db/sql "select sum(case when path='/folder1' then 1 else 0 end) from folder")
# folder2 has been removed, because at least two jobs within MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT are failed
test 0 == $($mc/db/sql "select sum(case when path='/folder2' then 1 else 0 end) from folder")
# folder3 shouldn't be touched
test 1 == $($mc/db/sql "select sum(case when path='/folder3' then 1 else 0 end) from folder")
