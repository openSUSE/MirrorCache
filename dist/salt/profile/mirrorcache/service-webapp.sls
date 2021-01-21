'systemctl set-environment MIRRORCACHE_TOP_FOLDERS="debug distribution factory history ports repositories source tumbleweed update"':
  cmd.run

'systemctl set-environment MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb':
  cmd.run:
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb

'systemctl set-environment MOJO_REVERSE_PROXY=1':
  cmd.run

mirrorcache-service-webapp:
  service.running:
    - name: mirrorcache
    - enable: true
