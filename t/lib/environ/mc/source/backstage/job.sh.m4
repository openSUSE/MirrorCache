set -e

__workdir/../gen_env
source __workdir/../conf.env

__workdir/../db/status >& /dev/null || __workdir/../db/start ${MIRRORCACHE_DB_START_OPTS:-}
[ -e __workdir/../db/sql_mc_test ] || __workdir/../db/create_db mc_test

(
cd __workdir
extra=""
[ "$#" -ne 1 ] || extra=-e
__srcdir/script/mirrorcache minion job $extra "$@"
)
