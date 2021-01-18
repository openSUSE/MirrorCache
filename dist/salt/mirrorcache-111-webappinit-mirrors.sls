/usr/share/mirrorcache/sql/mirrors-de.sql:
  file.managed:
    - mode: 644
    - source: salt://files/mirrors-de.sql

'psql -f /usr/share/mirrorcache/sql/mirrors-de.sql':
  cmd.run:
    - unless: test 1 == $(psql -tAc "select 1 from server limit 1")
    - runas: mirrorcache
