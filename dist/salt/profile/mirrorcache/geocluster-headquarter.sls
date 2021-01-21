/var/lib/GeoIP/GeoLite2-City.mmdb:
  file.exists

"echo insert into subsidiary select 'eu','mirrorcache-eu.opensuse.org',null | psql -c":
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from subsidiary where region = 'eu' limit 1") || test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - runas: mirrorcache

"echo insert into subsidiary select 'na','mirrorcache-na.opensuse.org',null | psql -c":
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from subsidiary where region = 'na' limit 1") || test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - runas: mirrorcache
