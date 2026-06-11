if [ "$MIRRORCACHE_DB_PROVIDER" == mariadb ]; then
    ln -sf __workdir/ma __workdir/db
    rm -r __workdir/pg
    # Patch the compiled ma/start script so that all manual/standalone db starts also respect MIRRORCACHE_DB_AIO=0
    sed -i 's,\$eatmydata /usr/sbin/mariadbd,extra_opts=""; if [ "${MIRRORCACHE_DB_AIO:-1}" = "0" ]; then extra_opts="--innodb-use-native-aio=0"; fi; \$eatmydata /usr/sbin/mariadbd \$extra_opts,g' __workdir/ma/start
else
    ln -sf __workdir/pg __workdir/db
    rm -r __workdir/ma
fi

__srcdir/tools/generate-packed-assets || __srcdir/tools/generate-packed-assets || __srcdir/tools/generate-packed-assets

mkdir __workdir/cwd
(
cd __workdir/cwd
ln -s ../../.sass-cache .
mkdir .cache
)

