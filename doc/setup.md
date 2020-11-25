# Setup

## Common Setup

### Environment variables

MirrorCache can be configured with following environment variables:
  * MIRRORCACHE_ROOT defines location of files, which needs redirection. It may be url or file, e.g. `MIRRORCACHE_ROOT=http://download.opensuse.org` or `MIRRORCACHE_ROOT=/srv/mirrorcache`.
  * MIRRORCACHE_TOP_FOLDERS are used to automatically redirect /folder to /download/folder.
  * For reference of using MOJO_LISTEN variable refer Mojolicious documentation, e.g. `MOJO_LISTEN=http://*:8000`
  * It is recommended to run MirrorCache daemon behind another streamline WebService, e.g. Apache or haproxy. Thus `MOJO_REVERSE_PROXY=1` will be needed.

Without any database configuration MirrorCache will attempt to connect to database 'mirrorcache' on default PostgreSQL port 5432.
Following variables can be used to configure database access:
  * MIRRORCACHE_DBUSER (default empty)
  * MIRRORCACHE_DBPASS (default empty)
  * TEST_PG or MIRRORCACHE_DSN , e.g. MIRRORCACHE_DSN='DBI:Pg:dbname=mc_dev;host=/path/to/pg'`
If neither TEST_PG nor MIRRORCACHE_DSN is defined, following variables are used:
  * MIRRORCACHE_DB (default 'mirrorcache')
  * MIRRORCACHE_DBHOST (default empty)
  * MIRRORCACHE_DBPORT (default empty)

### Database schema and initial data
  Before starting services, schema.sql file must be loaded into database.
  Source distribution:
    `sql/schema.sql`
  Package:
    `/usr/share/mirrorcache/sql/schema.sql`
    
### GeoIP location
  * If environment variable MIRRORCACHE_CITY_MMDB is defined, the app will attempt to detect country of the request and find a mirror in the same country, e.g. `MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb`.
  * Refer Maxmind geoip2 on how to obtain such file.
  * Additional dependencies must be installed as well for GeoIP location to work: perl modules Mojolicious::Plugin::ClientIP and MaxMind::DB::Reader:
```
zypper in perl-App-cpanminus make gcc
cpanm Mojolicious::Plugin::ClientIP --sudo
cpanm MaxMind::DB::Reader --sudo
```

## Types of install

### Install package

An example for openSUSE 15.2 
```bash
zypper addrepo https://mirrorcache.opensuse.org/repositories/devel:languages:perl/openSUSE_Leap_15.2 devel:languages:perl
zypper addrepo https://mirrorcache.opensuse.org/repositories/home:andriinikitin/openSUSE_Leap_15.2 mc
zypper --gpg-auto-import-keys --no-gpg-checks refresh
zypper install MirrorCache

zypper install postgresql postgresql-server
systemctl set-environment MIRRORCACHE_ROOT=http://download.opensuse.org
systemctl set-environment MOJO_LISTEN=http://*:8000
systemctl start postgresql

sudo -u postgres createuser mirrorcache
sudo -u postgres createdb mirrorcache
sudo -u mirrorcache psql -f /usr/share/mirrorcache/sql/schema.sql mirrorcache

systemctl start mirrorcache
systemctl start mirrorcache-backstage

# currently 3 jobs must run continuously
sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule_from_misses
sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule
sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e mirror_scan_schedule_from_misse
```

### Setup systemd from source

1. Install prerequisites. 
The project is based on Perl Mojolicious framework and set of Perl packages.
The best way to install them is to reuse zypper and cpanm commands from CI environment:
   `t/environs/lib/Dockerfile.environs`

You may skip installing MaxMind::DB::Reader and Mojolicious::Plugin::ClientIP if you don't need Geolocation detection, if you don't need MirrorCache to find a mirror in client's country. From now on it will be referenced as 'Geolocation feature'.

2. You will may GeoIP database (optional, if 'Geolocation feature' is needed).
`/var/lib/GeoIP/GeoLite2-City.mmdb`
In such case you will also need following command in next step:
```bash
systemctl set-environment MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb
```

3. Setup
Use following script as root for inspiration (see also t/systemd/01-smoke.t)
```bash
# assume local PostgreSQL server is up and running with default config
make install
make setup_production_assets
make setup_system_user
make setup_system_db

systemctl set-environment MIRRORCACHE_ROOT=http://download.opensuse.org
systemctl set-environment MOJO_LISTEN=http://*:8000

systemctl start mirrorcache
systemctl start mirrorcache-backstage

sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule_from_misses
sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e folder_sync_schedule
sudo -u mirrorcache /usr/share/mirrorcache/script/mirrorcache minion job -e mirror_scan_schedule_from_misses

# log into UI and provide admin rights to the user:
sudo -u mirrorcache psql -c "update acc set is_admin=1 where nickname='myusername'" mirrorcache
# add mirrors using UI or sql
sudo -u mirrorcache psql -c "insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au',''" mirrorcache
```

### Development setup

1. Install prerequisites.
The project is based on Perl Mojolicious framework and set of Perl packages.
The best way to install them is to reuse zypper and cpanm commands from CI environment:
   `t/environs/lib/Dockerfile.environs`

You may skip installing MaxMind::DB::Reader and Mojolicious::Plugin::ClientIP if you don't need Geolocation detection, if you don't need MirrorCache to find a mirror in client's country. From now on it will be referenced as 'Geolocation feature'.

2. You will may GeoIP database (optional, if 'Geolocation feature' is needed).
`/var/lib/GeoIP/GeoLite2-City.mmdb`

3. You will need PostgreSQL server running, create database for mirrorcache and create tables:
```
createdb mc_dev
psql -f sql/schema.sql mc_dev
```
It is possible to run PostgreSQL on dedicated server as well.


4. Example parameters to start WebApp:
```bash
TEST_PG='DBI:Pg:dbname=mc_dev;host=/path/to/pg' \
MIRRORCACHE_ROOT=http://download.opensuse.org \
MIRRORCACHE_TOP_FOLDERS='debug distribution factory history ports repositories source tumbleweed update' \
MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb \
MOJO_REVERSE_PROXY=1 \
MOJO_LISTEN=http://*:8000 \
script/mirrorcache daemon
```

5. To start background jobs:
```bash
TEST_PG='DBI:Pg:dbname=mc_dev;host=/path/to/pg' \
MIRRORCACHE_ROOT=http://download.opensuse.org \
script/mirrorcache backstage run -j 16
```

6. Currently three jobs must be scheduled once and then they will be continuously running:
```bash
script/mirrorcache minion job -e folder_sync_schedule_from_misses
script/mirrorcache minion job -e folder_sync_schedule
script/mirrorcache minion job -e mirror_scan_schedule_from_misses
```

7. Add mirrors using UI or sql, e.g.:
```sql
insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'ftp.iinet.net.au','/pub/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'mirror.intergrid.com.au','/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'mirror.internode.on.net','/pub/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'ftp.netspace.net.au','/pub/opensuse','t','au','';
```

8. Log in using UI and add admin privilege to the user:
```sql
update acc set is_admin=1 where nickname='myusername';
```

### Development setup using environs framework

Environs framework provides a way to manage development setup of various products without root permissions.
Such approach is useful in manual and integration testing, especially when various topologies are required.
MirrorCache project uses environs framework in CI, e.g. to start several Apache instances, configure them as mirrors, try different scenarios: 
http/https redirection, one of mirrors is down, a file is gone from a mirror, etc.

E.g. steps 2 - 7 above using environs framework.
```bash
# clone environs framework
git clone https://github.com/andrii-suse/environs
cd environs
# First choose a slot to use in script, mc0 - mc9 are available, so several instances at the same time
# here we will use slot 1 => mc1, first parameter is where MirrorCache sources are located
./environ.sh mc1 ~/github/MirrorCache
# pg1-system2 will setup local instance of Postgres server with data directory in pg1-system2/dt/
./environ.sh pg1-system2
pg1*/start.sh
pg1*/create.sh db mc
pg1*/sql.sh -f ~/github/MirrorCache/sql/schema.sql mc
mc1*/configure_db.sh pg1

MIRRORCACHE_ROOT=http://download.opensuse.org \
MIRRORCACHE_TOP_FOLDERS='debug distribution factory history ports repositories source tumbleweed update' \
MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb \
MOJO_REVERSE_PROXY=1 \
mc1*/start.sh

MIRRORCACHE_ROOT=http://download.opensuse.org \
mc1*/backstage/start.sh
mc1*/backstage/job.sh folder_sync_schedule_from_misses
mc1*/backstage/job.sh folder_sync_schedule
mc1*/backstage/job.sh mirror_scan_schedule_from_misses

pg1*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au',''" mc

# check status
pg1*/status.sh
mc1*/status.sh
mc1*/backstage/status.sh
```
