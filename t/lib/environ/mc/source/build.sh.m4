if [ "$MIRRORCACHE_DB_PROVIDER" == mariadb ]; then
    ln -sf __workdir/ma __workdir/db
    rm -r __workdir/pg
else
    ln -sf __workdir/pg __workdir/db
    rm -r __workdir/ma
fi

__srcdir/tools/generate-packed-assets || __srcdir/tools/generate-packed-assets || __srcdir/tools/generate-packed-assets
