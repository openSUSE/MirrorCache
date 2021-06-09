mirrorcache-service-posgresql:
  service.running:
    - name: postgresql
    - enable: true

mirrorcache-dbobjects:
  postgres_database.present:
    - name: mirrorcache
    - db_user: postgres

  postgres_user.present:
    - name: mirrorcache
    - db_user: postgres

'psql -c "ALTER DATABASE mirrorcache OWNER TO mirrorcache"':
  cmd.run:
    - runas: postgres

{%- if grains.id == 'mirrorcache.opensuse.org' %}
insert-regions:
  cmd.run:
    - runas: mirrorcache
    - name:
        psql -c "insert into subsidiary(region, hostname) select 'eu', 'mirrorcache-eu.opensuse.org'"
        psql -c "insert into subsidiary(region, hostname) select 'na', 'mirrorcache-us.opensuse.org'"
{%- endif %}

/usr/share/mirrorcache/sql/mirrors.sql:
  file.managed:
    - mode: 644
    - user: mirrorcache
{%- if grains.id == 'mirrorcache.suse.de'  %}
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-internal.sql
{%- elif grains.id == 'mirrorcache-eu.opensuse.org' %}
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-eu.sql
{%- elif grains.id == 'mirrorcache-us.opensuse.org' %}
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-na.sql
{%- elif grains.id == 'mirrorcache.opensuse.org' %}
    - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/sql/mirrors-rest.sql
{%- endif %}

'psql -f /usr/share/mirrorcache/sql/mirrors.sql':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from server limit 1")
    - runas: mirrorcache
    - unless: test ! -f /usr/share/mirrorcache/sql/mirrors.sql

conf-env:
  file.managed:
    - user: mirrorcache
    - mode: 0644
    - names:
      - /usr/share/mirrorcache/conf.env:
{%- if grains.osfullname == 'SLES'  %}
        - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/conf.env.SLES
{%- else %}
        - source: salt://profile/mirrorcache/files/usr/share/mirrorcache/conf.env.openSUSE
{%- endif %}

'echo "MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb" >> /usr/share/mirrorcache/conf.env':
  cmd.run:
    - unless: test ! -f /var/lib/GeoIP/GeoLite2-City.mmdb

{%- if grains.id == 'mirrorcache-eu.opensuse.org' %}
'echo -e "MIRRORCACHE_REGION=eu\nMIRRORCACHE_HEADQUARTER=mirrorcache.opensuse.org" >> /usr/share/mirrorcache/conf.env':
  cmd.run:
{%- elif grains.id == 'mirrorcache-na.opensuse.org' %}
'echo -e "MIRRORCACHE_REGION=na\nMIRRORCACHE_HEADQUARTER=mirrorcache.opensuse.org" >> /usr/share/mirrorcache/conf.env':
  cmd.run:
{%- endif %}
