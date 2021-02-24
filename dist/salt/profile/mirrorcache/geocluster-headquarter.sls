/var/lib/GeoIP/GeoLite2-City.mmdb:
  file.exists

"psql -c \"insert into subsidiary(region,hostname,uri) select 'eu','mirrorcache-eu.opensuse.org',null\"":
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from subsidiary where region = 'eu' limit 1") || test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - runas: mirrorcache

"psql -c \"insert into subsidiary(region,hostname,uri) select 'na','mirrorcache-na.opensuse.org',null\"":
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from subsidiary where region = 'na' limit 1") || test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - runas: mirrorcache
