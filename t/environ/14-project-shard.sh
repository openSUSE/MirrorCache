#!lib/test-in-container-environ.sh
set -ex

# contains everything, just place holder and will not be really used in this test
mcall=$(environ mc2 $(pwd))

mkdir -p $mcall/dt/repositories/home1
mkdir -p $mcall/dt/repositories/home2
mkdir -p $mcall/dt/folder1/dir1
mkdir -p $mcall/dt/folder1/dir2
mkdir -p $mcall/dt/folder2/dir1
mkdir -p $mcall/dt/folder2/dir2

# contains /repositories
mcrepo=$(environ mc3 $(pwd))
# contains the rest
mcmain=$(environ mc4 $(pwd))


# deploy DB
$mcall/backstage/shoot

$mcall/sql "insert into project(name,path) select 'proj1','/folder1'"
$mcall/sql "insert into project(name,path) select 'proj 2','/folder2'"
$mcall/sql "insert into project(name,path,shard) select 'repositories','/repositories','repositories'"

# gen config and link DB
$mcrepo/gen_env MIRRORCACHE_TOP_FOLDERS="'repositories'"
rm -r $mcrepo/db
ln -s $mcall/db $mcrepo/db
$mcrepo/start

$mcmain/gen_env MIRRORCACHE_TOP_FOLDERS="'folder1 folder2'"
rm -r $mcmain/db
ln -s $mcall/db $mcmain/db
$mcmain/start

( cd $mcrepo/dt ; ln -s $mcall/dt/repositories repositories )
( cd $mcmain/dt ; ln -s $mcall/dt/folder1 folder1; ln -s $mcall/dt/folder2 folder2 )

echo $mcall/dt/{folder1,folder2}/{dir1,dir2}/{file1.1,file2.1}.dat | xargs -n 1 touch
echo $mcall/dt/repositories/{home1,home2}/{file1.1,file2.1}.dat | xargs -n 1 touch

echo smoke check files exist
$mcrepo/curl -I /repositories/home1/file1.1.dat | grep '200 OK'
$mcmain/curl -I /folder1/dir1/file1.1.dat       | grep '200 OK'

$mcmain/backstage/job folder_sync_schedule_from_misses
$mcmain/backstage/job folder_sync_schedule

$mcmain/backstage/shoot
$mcrepo/backstage/shoot -q repositories

$mcmain/sql_test 2 ==  'select count(*) from folder'
$mcmain/sql_test 2 ==  'select count(*) from folder where sync_scheduled > sync_requested'
$mcmain/sql_test 2 ==  "select count(*) from minion_jobs where task = 'folder_sync'"
$mcmain/sql_test 2 ==  "select count(*) from minion_jobs where task = 'folder_sync' and state = 'finished'"
$mcmain/sql_test 1 ==  "select count(*) from minion_jobs where task = 'folder_sync' and queue = 'default' "
$mcmain/sql_test 1 ==  "select count(*) from minion_jobs where task = 'folder_sync' and queue = 'repositories'"

echo success
