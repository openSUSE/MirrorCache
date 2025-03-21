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
    /repositories/Java:/bootstrap/openSUSE_Factory/repodata/001-primary.xml.gz
    /tumbleweed/repo/oss/noarch/apparmor-docs-3.0.7-3.1.noarch.rpm
    /tumbleweed/repo/oss/x86_64/cargo1.64-1.64.0-1.1.x86_64.rpm
    /distribution/leap/15.3/repo/oss/noarch/python-pyOpenSSL-doc-17.5.0-3.9.1.noarch.rpm
    /distribution/leap/15.3/repo/oss/noarch/libreoffice-l10n-or-6.1.3.2_7.3.6.2-6.28_150300.14.22.24.2.noarch.drpm
    /distribution/leap/15.1/repo/oss/noarch/yast2-online-update-configuration-4.1.0-lp151.1.1.noarch.rpm
    /repositories/isv:/ownCloud:/desktop/Ubuntu_20.04/01-Packages
    /repositories/isv:/ownCloud:/desktop/Ubuntu_18.04/01-Packages
    /repositories/home:/r/Fedora_33/repodata/5a3-filelists.xml.gz
    /repositories/multimedia:/apps/15.4/x86_64/qjackctl-0.9.7-lp154.59.30.x86_64.rpm
    /repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/01-Packages.gz
    /repositories/home:/u:/opsi:/4.2:/stable/Debian_11/amd64/opsi-utils_4.2.0.184-1_amd64.deb
    /repositories/openSUSE:/Tools/CentOS_7/repodata/2ca-filelists.xml.gz
    /repositories/home:/rzrfreefr/Raspbian_11/introspection-doc-generator_0.0.0-1.dsc
    /repositories/security:/shibboleth/CentOS_CentOS-6/repodata/01-primary.xml.gz
    /repositories/security:/shibboleth/RHEL_6/i686/xmltooling-schemas-1.5.0-2.1.el6.i686.rpm
    /repositories/home:/b1:/branches:/science:/EtherLab/Debian_Testing/arm64/libethercat_1.5.2-33_arm64.deb
    /repositories/home:/bgstack15:/aftermozilla/Debian_Unstable/01-Packages.gz
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

$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 hour', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '2 hour', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 day', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"
$mc/sql "insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time) select ip_sha1, agent, path, country, dt - interval '1 minute', mirror_id, folder_id, file_id, secure, ipv4, metalink, head, mirrorlist, pid, execution_time from stat"

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload | grep '"known_files_no_mirrors":"36","known_files_redirected":"108","known_files_requested":"108"' | grep '"total_requests":"144"'

$mc/sql "update agg_download set dt = dt - interval '1 day' where period = 'hour'"
$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload | grep '"known_files_no_mirrors":"36","known_files_redirected":"108","known_files_requested":"108"' | grep '"bytes_redirected":"1188"' | grep '"total_requests":"144"'
$mc/curl /rest/repdownload?period=day | grep '"known_files_no_mirrors":"144","known_files_redirected":"432","known_files_requested":"432"' | grep '"bytes_redirected":"4752"' | grep '"total_requests":"576"'


# $mc/curl /rest/repdownload?group=country
# $mc/curl /rest/repdownload?group=project
# $mc/curl /rest/repdownload?group=arch
# $mc/curl /rest/repdownload?group=os
# $mc/curl /rest/repdownload?group=os_version
$mc/curl /rest/repdownload?group=country,os_version,arch | grep -o '"arch":"amd64","bytes_redirected":"22","bytes_served":"0","bytes_total":"22","country":"cn"'

$mc/curl /rest/repdownload?group=mirror | grep -o '"mirror":"127.0.0.1:1304","total_requests":"'

$mc/backstage/job -e report -a '["once"]'
$mc/backstage/shoot

$mc/curl /rest/repdownload?group=mirror,country | grep '{"bytes_redirected":"396","bytes_served":"0","bytes_total":"396","country":"de",' | grep -o '"known_files_no_mirrors":"0","known_files_redirected":"36","known_files_requested":"36","mirror":"127.0.0.1:1314","total_requests":"36"}'

$mc/curl -Is /download/repositories/home:/b1:/branches:/science:/EtherLab/Debian_Testing/arm64/libethercat_1.5.2-33_arm64.deb | grep 'X-MEDIA-VERSION: 1.5.2'

$mc/curl -Is /download/repositories/home:/b1:/branches:/science:/EtherLab/Debian_Testing/arm64/libethercat_1.5.2-33_arm64.deb | grep 'X-MEDIA-VERSION: 1.5.2'

$mc/curl -Is '/download/distribution/leap/15.3/repo/oss/noarch/?REGEX=.*\.noarch\..?rpm' | grep 'X-MEDIA-VERSION: 17.5.0,7.3.6.2'

rc=0
$mc/curl -Is /download/repositories/home:/b1:/branches:/science:/EtherLab/Debian_Testing/ | grep -i X-MEDIA-VERSION || rc=$?
test $rc -gt 0

$mc/curl '/rest/repdownload?group=country&os=ubuntu'
$mc/curl '/rest/repdownload?group=country,mirror&type=rpm'
$mc/curl "/rest/repdownload?group=project&mirror=$(ap7/print_address)"
$mc/curl '/rest/repdownload?group=project,mirror&country=de'


$mc/backstage/job stat_agg_schedule
$mc/backstage/shoot

$mc/sql "insert into stat_agg select  dt - interval '1 day',  period, mirror_id, hit_count from stat_agg where period = 'day'"
$mc/sql "insert into stat_agg select  dt - interval '1 hour', period, mirror_id, hit_count from stat_agg where period = 'hour'"

$mc/curl /rest/efficiency
$mc/curl /rest/efficiency?period=day

# $mc/sql 'select * from agg_download_pkg'
$mc/sql_test 4 == "select count(*) from agg_download_pkg join metapkg on metapkg_id = id where period = 'day' and name = 'cargo1.64' group by period, dt"

$mc/curl /rest/package/1/stat_download | grep '"cnt_1d":"32","cnt_30d":"32","cnt_7d":"32","cnt_today":"8","cnt_total":"32"'
$mc/curl /rest/package/cargo1.64/stat_download_curr | grep '{"cnt_curr":0}'

$mc/curl -I /download/tumbleweed/repo/oss/x86_64/cargo1.64-1.64.0-1.1.x86_64.rpm | grep HTTP
$mc/curl -I /download/tumbleweed/repo/oss/x86_64/cargo1.64-1.64.0-1.1.x86_64.rpm | grep HTTP
$mc/curl -I /download/tumbleweed/repo/oss/x86_64/cargo1.64-1.64.0-1.1.x86_64.rpm | grep HTTP


$mc/curl /rest/package/cargo1.64/stat_download_curr | grep '{"cnt_curr":3}'

echo success
