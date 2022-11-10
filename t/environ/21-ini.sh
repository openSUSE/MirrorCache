#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=0

$mc/gen_env

echo "export MIRRORCACHE_INI=$mc/conf.ini" >> $mc/conf.env

# rc=0
# $mc/start || rc=$?
# test $rc -gt 0
# touch $mc/conf.ini

(
echo 'unset TEST_PG'
echo 'unset TEST_MYSQL'
echo 'unset MIRRORCACHE_ROOT'
) >> $mc/conf.env

(
echo root=$mc/dt
echo
echo [db]
if test "${MIRRORCACHE_DB_PROVIDER}" == mariadb; then
    echo "dsn=DBI:mysql:db=mc_test;mysql_socket=$mc/ma/.sock"
else
    echo db=mc_test
    echo host=$mc/pg/dt
fi
) >> $mc/conf.ini

$mc/start
$mc/status
$mc/stop

echo success
