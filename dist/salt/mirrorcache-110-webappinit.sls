dbobjects:
  postgres_database.present:
    - name: mirrorcache
    - db_user: postgres

  postgres_user.present:
    - name: mirrorcache
    - db_user: postgres

'psql -f /usr/share/mirrorcache/sql/schema.sql':
  cmd.run:
    - unless: test 1 == $(psql -tAc "select 1 from information_schema.tables where table_name='acc'")
    - runas: mirrorcache

