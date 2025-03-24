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

$mc/sql_test 1 == "select count(*) from stat where pkg = 'qjackctl'";

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

$mc/sql_test 6 ==  "select count(*) from pkg"
$mc/sql_test 6 ==  "select count(*) from metapkg"

$mc/curl /rest/search/packages

$mc/curl /rest/search/packages?ignore_path=tumbleweed
$mc/curl /rest/search/packages?ignore_file=python
$mc/curl "/rest/search/packages?ignore_file=python&ignore_path=tumbleweed"

$mc/curl "/rest/search/package_locations?package=xmltooling-schemas"
$mc/curl "/rest/search/package_locations?package=xmltooling-schemas&ignore_path=shibboleth"

echo success
