mkdir -p __workdir/dt
__workdir/gen_env
set -a
source __workdir/conf.env
set +a
test 1 != "${ENVIRON_MC_DB_AUTOSTART-1}" || __workdir/db/status >& /dev/null || __workdir/db/start "--transaction-isolation=read-committed"
[ -e __workdir/db/sql_mc_test ] || __workdir/db/create_db mc_test

(
cd __workdir/cwd

if test "${MIRRORCACHE_DAEMON:-}" == 1 ; then
    perl __srcdir/script/mirrorcache-daemon >> __workdir/.cout 2>> __workdir/.cerr &
    pid=$!
    echo $pid > __workdir/.pid
elif test "${MIRRORCACHE_HYPNOTOAD:-}" == 1 ; then
    export MIRRORCACHE_HYPNOTOAD_PID=__workdir/.pid
    perl __srcdir/script/mirrorcache-hypnotoad >> __workdir/.cout 2>> __workdir/.cerr &
    sleep 3
else
    __srcdir/script/mirrorcache daemon >> __workdir/.cout 2>> __workdir/.cerr &
    pid=$!
    echo $pid > __workdir/.pid
fi
)
sleep 0.1
__workdir/status || sleep 0.1
__workdir/status || sleep 0.2
__workdir/status || sleep 0.3
__workdir/status || sleep 0.4
__workdir/status || sleep 0.5
__workdir/status || sleep 0.7
__workdir/status || sleep 1
__workdir/status || sleep 2
__workdir/status || sleep 5
