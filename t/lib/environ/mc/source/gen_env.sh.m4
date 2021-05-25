set -e
[ -e __workdir/conf.env ] || (

echo export TEST_PG=\'$(__workdir/db/print_dbi mc_test)\'

echo "export MIRRORCACHE_ROOT=__workdir/dt
export MIRRORCACHE_CITY_MMDB=__srcdir/t/data/city.mmdb
export MOJO_LISTEN=http://127.0.0.1:__port
export MIRRORCACHE_AUTH_URL=''
export MIRRORCACHE_PERMANENT_JOBS=''
"

    for i in "$@"; do
        [ -z "$i" ] || echo "export $i" >> __workdir/conf.env
    done
) > __workdir/conf.env
