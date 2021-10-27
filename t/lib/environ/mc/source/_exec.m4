mkdir -p __workdir/dt
__workdir/gen_env
set -a
source __workdir/conf.env
set +a
__workdir/db/status >& /dev/null || __workdir/db/start
[ -e __workdir/db/sql_mc_test ] || __workdir/db/create_db mc_test
if test "${MIRRORCACHE_DAEMON:-}" == 1 ; then
    perl __srcdir/script/mirrorcache-daemon >> __workdir/.cout 2>> __workdir/.cerr &
    pid=$!
else
    __srcdir/script/mirrorcache daemon >> __workdir/.cout 2>> __workdir/.cerr &
    pid=$!
fi
echo $pid > __workdir/.pid
sleep 0.2
