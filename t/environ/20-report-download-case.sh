#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

files=(
    /repositories/test1/debian_testing/arm64/libethercat_1.5.2-33_arm64.deb
    /repositories/test2/Debian_Testing/arm64/libethercat_1.5.2-33_arm64.deb
    )


for f in ${files[@]}; do
    for x in $mc $ap7 $ap8; do
        mkdir -p $x/dt${f%/*}
        echo 1111111111 > $x/dt$f
    done
done

$ap7/start
$ap8/start

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"


for f in ${files[@]}; do
    $mc/curl -Is /download$f
done

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

for f in ${files[@]}; do
    $mc/curl -Is /download$f | grep 302
    $mc/curl -Is /download$f?COUNTRY=de | grep 302
    $mc/curl -Is /download$f?COUNTRY=cn | grep 302
done

$mc/sql "update stat set dt = dt - interval '1 hour'"

$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg) select ip_sha1, agent, path, country, dt - interval '1 hour', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg) select ip_sha1, agent, path, country, dt - interval '2 hour', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg) select ip_sha1, agent, path, country, dt - interval '1 day', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg) select ip_sha1, agent, path, country, dt - interval '1 minute', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time, pkg from stat"

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload | grep '"known_files_no_mirrors":"4","known_files_redirected":"12","known_files_requested":"12"' | grep '"bytes_redirected":"132","bytes_served":"0","bytes_total":"132"'

echo success
