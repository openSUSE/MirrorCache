'echo "MIRRORCACHE_TOP_FOLDERS="debug distribution factory history ports repositories source tumbleweed update"" >> /usr/share/mirrorcache/conf.env':
  cmd.run

'echo "MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb" >> /usr/share/mirrorcache/conf.env':
  cmd.run:
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb

'echo "MOJO_REVERSE_PROXY=1" >> /usr/share/mirrorcache/conf.env':
  cmd.run
  
'echo "MIRRORCACHE_FALLBACK_HTTPS_REDIRECT=https://downloadcontent.opensuse.org" >> /usr/share/mirrorcache/conf.env':
  cmd.run

mirrorcache-service-webapp:
  service.running:
    - name: mirrorcache
    - enable: true
