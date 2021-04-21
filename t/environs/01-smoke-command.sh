#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

# make sure command job doesn't require MIRRORCACHE_ROOT
MIRRORCACHE_ROOT="" mc9*/backstage/job.sh folder_sync
MIRRORCACHE_ROOT="/fake/fake" mc9*/backstage/job.sh folder_sync
# make sure command job doesn't require MIRRORCACHE_CITY_MMDB
MIRRORCACHE_CITY_MMDB="" mc9*/backstage/job.sh folder_sync
