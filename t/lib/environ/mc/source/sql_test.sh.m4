set -e
res=$(__workdir/db/sql "$3")
test $1 $2 $res || ( echo FAILED: $1 $2 $res ; exit 1 )
