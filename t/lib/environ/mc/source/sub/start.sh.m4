set -e

__workdir/gen_env
source __workdir/conf.env

(
cd __workdir
__srcdir/script/mirrorcache daemon run >> __workdir/.cout 2>> __workdir/.cerr &

pid=$!
echo $pid > __workdir/.pid
sleep 3
__workdir/status
)
