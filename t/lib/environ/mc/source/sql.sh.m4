
test "$MIRRORCACHE_DB_PROVIDER" != mariadb || {

sql=${1/"'t'"/"1"}
sql=${sql/"'f'"/"0"}
sql=${sql/"extract(epoch from now())"/"unix_timestamp()"}

re="(update|insert|select)(.*)\s([a-z_A-Z]*)((\([a-z_0-9]*\))?) - interval '([0-9]+) (month|day|hour|minute|second)'(.*)$"
while [[ $sql =~ $re ]]; do
  sql="${BASH_REMATCH[1]}${BASH_REMATCH[2]}date_sub(${BASH_REMATCH[3]}${BASH_REMATCH[4]}, interval ${BASH_REMATCH[6]} ${BASH_REMATCH[7]})${BASH_REMATCH[8]}"
done

re="(update)(.*)\s([a-z_]*)((\(\))?) - interval '([0-9]+) hour ([0-9]+) minute ([^\s]+) second'(.*)$"
while [[ $sql =~ $re ]]; do
  sql="${BASH_REMATCH[1]}${BASH_REMATCH[2]}subtime(${BASH_REMATCH[3]}${BASH_REMATCH[4]}, '${BASH_REMATCH[6]}:${BASH_REMATCH[7]}:${BASH_REMATCH[8]}')${BASH_REMATCH[9]}"
done

re="(update)(.*)\s([a-z_]*)((\(\))?) - interval '([0-9]+) minute ([^\s]+) second'(.*)$"
while [[ $sql =~ $re ]]; do
  sql="${BASH_REMATCH[1]}${BASH_REMATCH[2]}subtime(${BASH_REMATCH[3]}${BASH_REMATCH[4]}, '0:${BASH_REMATCH[6]}:${BASH_REMATCH[7]}')${BASH_REMATCH[8]}"
done

re="extract(epoch from now())"
while [[ $sql =~ $re ]]; do
  sql="${BASH_REMATCH[1]}${BASH_REMATCH[2]}subtime(${BASH_REMATCH[3]}${BASH_REMATCH[4]}, '${BASH_REMATCH[6]}:${BASH_REMATCH[7]}:${BASH_REMATCH[8]}')${BASH_REMATCH[9]}"
done

set -- "$sql" "${@:2}"

}
__workdir/db/sql "$@"
