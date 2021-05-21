mkdir -p __workdir/dt
__workdir/gen_env
source __workdir/conf.env
__workdir/db/status >& /dev/null || __workdir/db/start
[ -e __workdir/db/sql_mc_test ] || __workdir/db/create_db mc_test
__srcdir/script/mirrorcache daemon >> __workdir/.cout 2>> __workdir/.cerr &
pid=$!
echo $pid > __workdir/.pid
