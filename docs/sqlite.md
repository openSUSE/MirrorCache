## use an SQLite DB

To store MirrorCache state in an SQLite DB, you need to do the extra steps documented below.

Install extra dependencies:

    zypper -n in perl-Minion-Backend-SQLite perl-DateTime-Format-SQLite

`/etc/mirrorcache/conf.env` should have:

    MIRRORCACHE_DB_PROVIDER=SQLite
    MIRRORCACHE_DB=/var/lib/mirrorcache/db.sqlite

To fill the DB:

    sqlite3 /var/lib/mirrorcache/db.sqlite
    update acc set is_admin=1 where nickname='MYUSERNAME';
    insert into server(hostname,urldir,enabled,country,region) select 'ftp.gwdg.de','/pub/linux/suse/opensuse','t','de','eu';

