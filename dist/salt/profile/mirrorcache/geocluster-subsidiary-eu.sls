/var/lib/GeoIP/GeoLite2-City.mmdb:
  file.exists

'systemctl set-environment MIRRORCACHE_REGION=eu && systemctl set-environment MIRRORCACHE_HEADQUARTER=mirrorcache.opensuse.org':
  cmd.run:
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
