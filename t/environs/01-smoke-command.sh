#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

# make sure command job doesn't require MIRRORCACHE_ROOT
MIRRORCACHE_ROOT="" $mc/backstage/job folder_sync
MIRRORCACHE_ROOT="/fake/fake" $mc/backstage/job folder_sync
# make sure command job doesn't require MIRRORCACHE_CITY_MMDB
MIRRORCACHE_CITY_MMDB="" $mc/backstage/job folder_sync
