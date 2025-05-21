set -e
[ -e __workdir/conf.env ] || (

echo __dbi='$(__workdir/db/print_dbi mc_test)'

if test "${MIRRORCACHE_DB_PROVIDER}" == mariadb; then
    echo export TEST_MYSQL='${__dbi//\/ma\//\/db\//}'
    echo export MARIADB_TLS_DISABLE_PEER_VERIFICATION=1
else
    echo export TEST_PG='${__dbi//\/pg\//\/db\//}'
fi

echo "export MIRRORCACHE_ROOT=__workdir/dt
export MIRRORCACHE_CITY_MMDB=__srcdir/t/data/city.mmdb
export MOJO_LISTEN=http://*:__port
export MIRRORCACHE_AUTH_URL=''
export MIRRORCACHE_PERMANENT_JOBS=''
export MIRRORCACHE_STAT_FLUSH_COUNT=1
export MIRRORCACHE_RECKLESS=1
export MIRRORCACHE_SCAN_MTIME_DIFF=0
export MARIADB_TLS_DISABLE_PEER_VERIFICATION=1
"

    for i in "$@"; do
        [ -z "$i" ] || echo "export $i" >> __workdir/conf.env
    done
) > __workdir/conf.env
