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

postgresql:
  pkg.installed:
    - refresh: True
    - pkgs:
      - postgresql
      - postgresql-server
      - MirrorCache

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


'psql -f /usr/share/mirrorcache/sql/schema.sql':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from information_schema.tables where table_name='acc' limit 1")
    - runas: mirrorcache

# job to aggregate misses and schedule file scans from MIRRORCACHE_ROOT (needed only if MIRRORCACHE_ROOT is url)
'/usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule_from_misses':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from minion_jobs where task='folder_sync_schedule_from_misses' and state in('active', 'inactive') limit 1")
    - runas: mirrorcache

# job to schedule periodical file rescans (needed only if MIRRORCACHE_ROOT is url)
'/usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from minion_jobs where task='folder_sync_schedule' and state in('active', 'inactive') limit 1")
    - runas: mirrorcache

# job to schedule mirror rescans
'/usr/share/mirrorcache/script/mirrorcache minion job -e mirror_scan_schedule_from_misses':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from minion_jobs where task='mirror_scan_schedule_from_misses' and state in('active', 'inactive') limit 1")
    - runas: mirrorcache


'systemctl set-environment MIRRORCACHE_ROOT=http://download.opensuse.org':
  cmd.run

'systemctl set-environment MOJO_REVERSE_PROXY=1':
  cmd.run

mirrorcache-service-webapp:
  service.running:
    - name: mirrorcache
    - enable: true

mirrorcache-service-backstage:
  service.running:
    - name: mirrorcache-backstage
    - enable: true
