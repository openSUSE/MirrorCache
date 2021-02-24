mirrorcache-perlrepo:
  pkgrepo.managed:
    - humanname: Perl repo
    - mirrorlist: http://mirrorcache.opensuse.org/download/repositories/devel:/languages:/perl/openSUSE_Leap_$releasever/
    - gpgcheck: 0

mirrorcache:
  pkgrepo.managed:
    - humanname: MirrorCache repo
    - mirrorlist: http://mirrorcache.opensuse.org/download/repositories/home:/andriinikitin/openSUSE_Leap_$releasever/
    - gpgcheck: 0

allservices:
  pkg.installed:
    - refresh: 0
    - pkgs:
      - postgresql
      - postgresql-server
      - MirrorCache

geofeature:
  pkg.installed:
    - refresh: 0
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb
    - pkgs:
      - gzip
      - gcc
      - make
      - perl-App-cpanminus

geofeature-cpan-plugin-clientip:
  cmd.run:
    - name: cpanm Mojolicious::Plugin::ClientIP --sudo
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb || perl -MMojolicious::Plugin::ClientIP -e 1

geofeature-cpan-maxmind-reader:
  cmd.run:
    - name: "cpanm MaxMind::DB::Reader --sudo || :"
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb || perl -Mcpanm MaxMind::DB::Reader -e 1
