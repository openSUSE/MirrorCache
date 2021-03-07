mirrorcache-service-backstage:
  service.running:
    - name: mirrorcache-backstage
    - enable: true

{% macro backstage_job(name) -%}
'/usr/share/mirrorcache/script/mirrorcache minion job -e  {{ name }}':
  cmd.run:
    - unless: test x1 == x$(psql -tAc "select 1 from minion_jobs where task='{{ name }}' and state in('active', 'inactive') limit 1")
    - runas: mirrorcache
{%- endmacro %}

# job to aggregate misses and schedule file scans from MIRRORCACHE_ROOT (needed only if MIRRORCACHE_ROOT is url)
{{ backstage_job('folder_sync_schedule_from_misses') }}

# job to schedule periodical file rescans (needed only if MIRRORCACHE_ROOT is url)
{{ backstage_job('folder_sync_schedule') }}

# job to schedule mirror rescans
{{ backstage_job('mirror_scan_schedule_from_misses') }}

# job to various cleanups
{{ backstage_job('cleanup') }}

# job to aggregate statistics
{{ backstage_job('stat_agg_schedule') }}


mirrorcache-service-webapp:
  service.running:
    - name: mirrorcache
    - enable: true
