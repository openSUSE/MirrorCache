#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL \
            MIRRORCACHE_HASHES_COLLECT=1 \
            MIRRORCACHE_ZSYNC_COLLECT=dat \
            MIRRORCACHE_HASHES_PIECES_MIN_SIZE=5

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo 11111 > $x/dt/folder1/file9.1.dat
done

$ap7/start
$ap7/curl /folder1/ | grep file1.1.dat

$ap8/start
$ap8/curl /folder1/ | grep file1.1.dat


$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"

$mc/curl -Is /download/folder1/file1.1.dat

$mc/sql "select * from stat"
$mc/sql_test 1 == "select count(*) from stat"

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

$mc/db/sql "select * from minion_jobs order by id"

$mc/curl /download/folder1/ | grep file1.1.dat
# check redirect is correct
$mc/curl -Is /download/folder1 | grep -i 'Location: /download/folder1/'

tmp_tables1="$(test "$MIRRORCACHE_DB_PROVIDER" != mariadb || $mc/sql 'show global status like '\''%tmp%disk%'\''')"

# only ap7 is in US
$mc/curl -Is /download/folder1/file1.1.dat | grep -C10 302 | grep "$($ap7/print_address)"

tmp_tables2="$(test "$MIRRORCACHE_DB_PROVIDER" != mariadb || $mc/sql 'show global status like '\''%tmp%disk%'\''')"
# test the main query doesn't create tmp tables on disk (relevant only for mariadb)
test "$tmp_tables1" == "$tmp_tables2"

###################################
# test files are removed properly
rm $mc/dt/folder1/file1.1.dat

# resync the folder
$mc/backstage/job -e folder_sync -a '["/folder1"]'
$mc/backstage/shoot

$mc/curl -s /download/folder1/ | grep file1.1.dat || :
if $mc/curl -s /download/folder1/ | grep file1.1.dat ; then
    fail file1.1.dat was deleted
fi

$mc/curl -H "Accept: */*, application/metalink+xml" -s /download/folder1/file2.1.dat | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'
$mc/curl -s /download/folder1/file2.1.dat.metalink | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder1/file2.1.dat</url>'

$mc/curl -sL /                  | tidy --drop-empty-elements no
$mc/curl -sL /download/folder1/ | tidy --drop-empty-elements no

echo MIRRORCACHE_CUSTOM_FOOTER_MESSAGE='"Sponsored by openSUSE"' >> $mc/conf.env
$mc/stop
$mc/start

$mc/curl -sL /                  | tidy --drop-empty-elements no | grep 'Sponsored by openSUSE'
$mc/curl -sL /download/folder1/ | tidy --drop-empty-elements no | grep 'Sponsored by openSUSE'

$mc/curl -s '/download/folder1/file2.1.dat?mirrorlist' | grep 'http://127.0.0.1:1304/folder1/file2.1.dat'
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | grep 'http://127.0.0.1:1304/folder1/file2.1.dat'
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | tidy --drop-empty-elements no
$mc/curl -s '/download/folder1/file2.1.dat.mirrorlist' | grep "Origin: " | grep $($mc/print_address)/download/folder1/file2.1.dat
$mc/curl -s '/download/folder1/file2.1.dat.metalink'   | grep "origin"   | grep $($mc/print_address)/download/folder1/file2.1.dat

test "$($mc/curl -s /version)" != ""

# test metalink and mirrorlist when file is unknow yet
$mc/curl /download/folder3/file1.1.dat.metalink   | grep 'retry later'
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'retry later'

$mc/curl -iH "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" /download/folder3/file1.1.dat.metalink | grep 'retry later'

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

rc=0
$mc/curl /download/folder3/file1.1.dat.metalink   | grep 'retry later' || rc=$?
test $rc -gt 0
$mc/curl /download/folder3/file1.1.dat.metalink   | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/folder3/file1.1.dat</url>'

rc=0
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'retry later' || rc=$?
test $rc -gt 0
$mc/curl /download/folder3/file1.1.dat.mirrorlist | grep 'http://127.0.0.1:1304/folder3/file1.1.dat'

$mc/curl -A mybot-1.0 /download/folder3/file1.1.dat.mirrorlist | grep 'http://127.0.0.1:1304/folder3/file1.1.dat'

$mc/curl /rest/stat | grep '"bot":1,"hit":12,"miss":4'

$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 hour', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 day', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 minute', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"

$mc/backstage/job stat_agg_schedule
$mc/backstage/shoot

$mc/sql 'select * from stat_agg'
$mc/curl /rest/stat | grep '"hour":{"bot":2,"hit":24,"miss":8,"prev_bot":2,"prev_hit":24,"prev_miss":8}'

$mc/curl /download/folder3/file1.1.dat.metalink | xmllint --noout --format -
$mc/curl /download/folder3/file1.1.dat.meta4    | xmllint --noout --format -
$mc/curl /download/folder3/file1.1.dat.meta4    | grep '<url location="US" priority="1">http://127.0.0.1:1304/folder3/file1.1.dat</url>'


$mc/backstage/shoot -q hashes

$mc/curl -H "Accept: */*, application/metalink+xml, application/x-zsync" /download/folder1/file9.1.dat \
    | grep -C 20 "URL: http://$($ap7/print_address)/folder1/file9.1.dat" \
    | grep -C 20 "URL: http://$($ap8/print_address)/folder1/file9.1.dat" \
    | grep -C 20 "URL: http://$($mc/print_address)/download/folder1/file9.1.dat"


$mc/curl -iH "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" /download/folder1/file9.1.dat.metalink | grep '200 OK'

$mc/sql "update stat set dt = dt - interval '1 hour'"
$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload | grep '"known_files_no_mirrors":"8","known_files_redirected":"26","known_files_requested":"26"' | grep '"total_requests":"34"'

$mc/sql "update agg_download set dt = dt - interval '1 day' where period = 'hour'"
$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload?period=day | grep '"known_files_no_mirrors":"16","known_files_redirected":"57","known_files_requested":"57"' | grep '"total_requests":"73"'

echo success
