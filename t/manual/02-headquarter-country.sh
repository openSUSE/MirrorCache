#!lib/test-in-container-environ.sh
set -ex

hq=$(environ mc1 $(pwd))
us=$(environ mc2 $(pwd))
eu=$(environ mc3 $(pwd))
oc=$(environ mc4 $(pwd))

hq_address=$($hq/print_address)
us_address=$($us/print_address)
us_interface=127.0.0.2
eu_address=$($eu/print_address)
eu_interface=127.0.0.3
oc_address=$($oc/print_address)
oc_interface=127.0.0.4

declare -A xtra
xtra[$hq]=''
xtra[$eu]="MIRRORCACHE_REGION=eu MIRRORCACHE_HEADQUARTER=$hq_address"
xtra[$us]="MIRRORCACHE_REGION=us MIRRORCACHE_HEADQUARTER=$hq_address"
xtra[$oc]="MIRRORCACHE_REGION=oc MIRRORCACHE_HEADQUARTER=$hq_address"

for x in $hq $eu $us $oc; do

$x/gen_env MIRRORCACHE_RECKLESS=0 \
    MIRRORCACHE_ROOT=http://download.opensuse.org \
    MIRRORCACHE_REDIRECT=downloadcontent.opensuse.org \
    MIRRORCACHE_HYPNOTOAD=1 \
    MIRRORCACHE_PERMANENT_JOBS="'folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule cleanup stat_agg_schedule mirror_check_from_stat'" \
    MIRRORCACHE_TOP_FOLDERS="'debug distribution tumbleweed factory repositories'" \
    MIRRORCACHE_TRUST_AUTH=127.0.0.16 \
    MIRRORCACHE_PROXY_URL=http://$($x/print_address) \
    MIRRORCACHE_BACKSTAGE_WORKERS=4 \
    ${xtra[$x]}

    $x/backstage/start # start backstage here to deploy db
done


$hq/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-rest.sql mc_test
$hq/sql "update server set enabled='f' where region = 'oc'"
$hq/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-na.sql mc_test
$hq/sql "delete from server where country = 'us'"
$hq/sql "insert into subsidiary(hostname,region) select '$us_address','us'"
$hq/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$hq/sql "insert into subsidiary(hostname,region) select '$oc_address','oc'"
$hq/start

$us/start
$us/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-na.sql mc_test
$us/sql "delete from server where country != 'us'"

$eu/start
$eu/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-eu.sql mc_test

$oc/start
$oc/sql -f dist/salt/profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-rest.sql mc_test
$oc/sql "update server set enabled='f' where region != 'oc'"

# $hq/backstage/job -e folder_tree -a '["/distribution/leap/15.3"]'
# $us/backstage/job -e folder_tree -a '["/distribution/leap/15.3/iso"]'

curl -IL http://127.0.0.1:3110/distribution/leap/15.3/iso/openSUSE-Leap-15.3-2-NET-x86_64-Current.iso
sleep 10
$us/curl -IL /distribution/leap/15.3/iso/openSUSE-Leap-15.3-2-NET-x86_64-Current.iso
