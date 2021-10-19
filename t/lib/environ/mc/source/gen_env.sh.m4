set -e
[ -e __workdir/conf.env ] || (

echo export TEST_PG=\'$(__workdir/db/print_dbi mc_test)\'

echo "export MIRRORCACHE_ROOT=__workdir/dt
export MIRRORCACHE_CITY_MMDB=__srcdir/t/data/city.mmdb
export MOJO_LISTEN=http://*:__port
export MIRRORCACHE_AUTH_URL=''
export MIRRORCACHE_PERMANENT_JOBS=''
export MIRRORCACHE_STAT_FLUSH_COUNT=1
export MIRRORCACHE_TROTTLE=0
"

    for i in "$@"; do
        [ -z "$i" ] || echo "export $i" >> __workdir/conf.env
    done
) > __workdir/conf.env
