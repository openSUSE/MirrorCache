postgresql:
  pkg.installed:
    - refresh: True
    - pkgs:
      - postgresql
      - postgresql-server

/var/run/postgresql:
    file.directory:
    - user: postgres
    - makedirs: True
