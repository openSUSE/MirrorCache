mirrorcache-service-backstage:
  service.running:
    - name: mirrorcache-backstage
    - enable: true

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
