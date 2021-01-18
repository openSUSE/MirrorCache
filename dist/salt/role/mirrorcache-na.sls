include:
  - profile.mirrorcache

/usr/share/mirrorcache/sql/mirrors-na.sql:
  file.managed:
    - mode: 644
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-na.sql

'psql -f /usr/share/mirrorcache/sql/mirrors-na.sql':
  cmd.run:
    - unless: test x1 == "x$(psql -tAc 'select 1 from server limit 1')"
    - runas: mirrorcache
