set -e
last=${@:$#} # last parameter
other=${*%${!#}} # all parameters except the last
res=$(__workdir/db/sql "$last")
test $other $res || ( echo FAILED: $other $res ; exit 1 )
