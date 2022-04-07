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

&>/dev/null echo __workdir/../sql '
 drop function minion_lock;
 DELIMITER //
 create FUNCTION minion_lock( $1 VARCHAR(191), $2 INTEGER, $3 INTEGER) RETURNS BOOL
  NOT DETERMINISTIC MODIFIES SQL DATA SQL SECURITY INVOKER
BEGIN
  DECLARE new_expires TIMESTAMP DEFAULT DATE_ADD( NOW(), INTERVAL 1*$2 SECOND );
  IF (SELECT COUNT(*) >= $3 FROM minion_locks WHERE name = $1)
  THEN
    RETURN FALSE;
  END IF;
  IF new_expires > NOW()
  THEN
    INSERT INTO minion_locks (name, expires) VALUES ($1, new_expires);
  END IF;
  RETURN TRUE;
END
//
DELIMITER ;
'

__workdir/status
)
