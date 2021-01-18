service1:
  service.running:
   - name: postgresql
   - enable: true

service2:
  service.running:
   - name: mirrorcache
   - enable: true

service3:
  service.running:
   - name: mirrorcache-backstage
   - enable: true

haproxy:
  service.running:
    - enable: true

