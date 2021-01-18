/etc/haproxy/haproxy.cfg:
  file.managed:
    - mode: 644
    - source: salt://files/haproxy.cfg
