mirrorcache-service-posgresql:
  service.running:
    - name: postgresql
    - enable: true

mirrorcache-dbobjects:
  postgres_database.present:
    - name: mirrorcache
    - db_user: postgres

  postgres_user.present:
    - name: mirrorcache
    - db_user: postgres


'psql -f /usr/share/mirrorcache/sql/schema.sql':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from information_schema.tables where table_name='acc' limit 1")
    - runas: mirrorcache
