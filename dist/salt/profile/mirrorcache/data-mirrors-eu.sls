/usr/share/mirrorcache/sql/mirrors-eu.sql:
  file.managed:
    - mode: 644
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-eu.sql

'psql -f /usr/share/mirrorcache/sql/mirrors-eu.sql':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from server where country = 'de' limit 1")
    - runas: mirrorcache
