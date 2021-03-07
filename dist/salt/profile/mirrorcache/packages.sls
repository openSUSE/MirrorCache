packages:
  pkg.installed:
    - refresh: 0
    - pkgs:
      - postgresql
      - postgresql-server
      - MirrorCache

packages-geofeature:
  pkg.installed:
    - refresh: 0
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - pkgs:
      - perl-Mojolicious-Plugin-ClientIP
      - perl-MaxMind-DB-Reader
