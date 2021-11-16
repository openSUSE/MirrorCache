set -e

__workdir/../gen_env
source __workdir/../conf.env

__workdir/../db/status >& /dev/null || __workdir/../db/start
[ -e __workdir/../db/sql_mc_test ] || __workdir/../db/create_db mc_test

(
cd __workdir
__srcdir/script/mirrorcache backstage run -C 1 -j ${MIRRORCACHE_BACKSTAGE_WORKERS:-2} >> __workdir/.cout 2>> __workdir/.cerr &

pid=$!
echo $pid > __workdir/.pid
sleep 0.2
__workdir/status
)
