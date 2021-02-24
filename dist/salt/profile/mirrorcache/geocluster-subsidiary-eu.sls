/var/lib/GeoIP/GeoLite2-City.mmdb:
  file.exists

'echo -e "MIRRORCACHE_REGION=eu\nMIRRORCACHE_HEADQUARTER=mirrorcache.opensuse.org" >> /usr/share/mirrorcache/conf.env':
  cmd.run:
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
