# Setup

## Common Setup

### Environment variables

MirrorCache can be configured with following environment variables:
  * MIRRORCACHE_ROOT (required): defines location of files, which needs redirection. It may be url, local folder or rsync address, e.g. `MIRRORCACHE_ROOT=http://download.opensuse.org` or `MIRRORCACHE_ROOT=/srv/mirrorcache` or `MIRRORCACHE_ROOT=rsync://user:password@myhost.com/module`. (Note that you must install additionally `perl-Digest-MD4` if rsync url needs password verification).
  * MIRRORCACHE_AUTH_URL (optional) may contain remote openid server url (default https://www.opensuse.org/openid/user/). if explicitly set to empty value - all login attempt will be allowed and user set to 'Demo'.
  * MIRRORCACHE_TOP_FOLDERS (space separated values) may be set to automatically redirect /folder to /download/folder.
  * For reference of using MOJO_LISTEN variable refer Mojolicious documentation, e.g. `MOJO_LISTEN=http://*:8000`
  * It is recommended to run MirrorCache daemon behind another streamline WebService, e.g. Apache or haproxy. Thus `MOJO_REVERSE_PROXY=1` will be needed.
  * MIRRORCACHE_REDIRECT is needed for use when MIRRORCACHE_ROOT is set to remote address. Requests will be redirected to this location when no mirror is found, e.g. MIRRORCACHE_REDIRECT=downloadcontent.opensuse.org
  * MIRRORCACHE_METALINK_PUBLISHER may be set to customize publisher in metalink generation.
  * MIRRORCACHE_METALINK_PUBLISHER_URL may be set to customize url of publisher in metalink generation.
  * MIRRORCACHE_BRANDING loads files from [templates/branding](/templates/branding). Use the `default` folder as a base for your own branding and set this environment variable to the name of the newly created folder.
  * MIRRORCACHE_VPN_PREFIX - MirrorCache will use column server.hostname_vpn for redirecting if client IP has prefix as defined by MIRRORCACHE_VPN_PREFIX.

Without any database configuration MirrorCache will attempt to connect to database 'mirrorcache' on default PostgreSQL port 5432.
Following variables can be used to configure database access:
  * MIRRORCACHE_DBUSER (default empty)
  * MIRRORCACHE_DBPASS (default empty)
  * TEST_PG or MIRRORCACHE_DSN , e.g. MIRRORCACHE_DSN='DBI:Pg:dbname=mc_dev;host=/path/to/pg'`
If neither TEST_PG nor MIRRORCACHE_DSN is defined, following variables are used:
  * MIRRORCACHE_DB (default 'mirrorcache')
  * MIRRORCACHE_DBHOST (default empty)
  * MIRRORCACHE_DBPORT (default empty)

### GeoIP location
  * If environment variable MIRRORCACHE_CITY_MMDB is defined, the app will attempt to detect country of the request and find a mirror in the same country, e.g. `MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb`.
  * Refer Maxmind geoip2 on how to obtain such file.
  * Additional dependencies must be installed as well for GeoIP location to work: perl modules Mojolicious::Plugin::ClientIP and MaxMind::DB::Reader :
```
zypper in perl-Mojolicious-Plugin-ClientIP perl-MaxMind-DB-Reader
```

## Types of install

### Install package

An example for openSUSE 15.2
```bash
zypper ar https://mirrorcache.opensuse.org/repositories/home:andriinikitin:/MirrorCache/openSUSE_Leap_15.2 mc
zypper --gpg-auto-import-keys --no-gpg-checks refresh
zypper install MirrorCache

zypper install postgresql postgresql-server
systemctl enable postgresql

sudo -u postgres createuser mirrorcache
sudo -u postgres createdb mirrorcache

# the services read environment variables from /etc/mirrorcache/conf.env by default
echo "MIRRORCACHE_ROOT=http://download.opensuse.org
MIRRORCACHE_TOP_FOLDERS='debug distribution factory history ports repositories source tumbleweed update'
MOJO_LISTEN=http://*:8000
" >> /etc/mirrorcache/conf.env

systemctl enable mirrorcache
systemctl enable mirrorcache-backstage
```

### Setup systemd from source

1. Install prerequisites.
The project is based on Perl Mojolicious framework and set of Perl packages.
The best way to install them is to reuse zypper and cpanm commands from CI environment:
   `t/environ/lib/Dockerfile.environ`

You may skip installing MaxMind::DB::Reader and Mojolicious::Plugin::ClientIP if you don't need Geolocation detection, if you don't need MirrorCache to find a mirror in client's country. From now on it will be referenced as 'Geolocation feature'.

2. You may need GeoIP database (optional, if 'Geolocation feature' is needed).
`/var/lib/GeoIP/GeoLite2-City.mmdb`
In such case you will also need following command in next step:
```bash
echo MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb >> /etc/mirrorcache/conf.env
```

3. Setup
Use following script as root for inspiration (see also t/systemd/01-smoke.t)
```bash
# assume local PostgreSQL server is up and running with default config
make install
make setup_production_assets
make setup_system_user
make setup_system_db
# the services read environment variables from /etc/mirrorcache/conf.env by default
echo "MIRRORCACHE_ROOT=http://download.opensuse.org
MIRRORCACHE_TOP_FOLDERS='debug distribution factory history ports repositories source tumbleweed update'
MOJO_LISTEN=http://*:8000
" >> /etc/mirrorcache/conf.env

systemctl enable mirrorcache
systemctl enable mirrorcache-backstage

# log into UI and provide admin rights to the user:
sudo -u mirrorcache psql -c "update acc set is_admin=1 where nickname='myusername'" mirrorcache
# add mirrors using UI or sql
sudo -u mirrorcache psql -c "insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au',''" mirrorcache
```

### Development setup

1. Install prerequisites.
The project is based on Perl Mojolicious framework and set of Perl packages.
The best way to install them is to reuse zypper and cpanm commands from CI environment:
   `t/environ/lib/Dockerfile.environ`

You may skip installing MaxMind::DB::Reader and Mojolicious::Plugin::ClientIP if you don't need Geolocation detection, if you don't need MirrorCache to find a mirror in client's country. From now on it will be referenced as 'Geolocation feature'.

2. You may need GeoIP database (optional, if 'Geolocation feature' is needed).
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

6. Add mirrors using UI or sql, e.g.:
```sql
insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'ftp.iinet.net.au','/pub/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'mirror.intergrid.com.au','/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'mirror.internode.on.net','/pub/opensuse','t','au','';
insert into server(hostname,urldir,enabled,country,region) select 'ftp.netspace.net.au','/pub/opensuse','t','au','';
```

7. Log in using UI and add admin privilege to the user:
```sql
update acc set is_admin=1 where nickname='myusername';
```

### Development setup using environ framework

environ framework provides a way to manage development setup of various products without root permissions.
Such approach is useful in manual and integration testing, especially when various topologies are required.
MirrorCache project uses environ framework in CI, e.g. to start several Apache instances, configure them as mirrors, try different scenarios:
http/https redirection, one of mirrors is down, a file is gone from a mirror, etc.

E.g. steps 2 - 7 above using environ framework.
```bash
# Needs environ utility installed, as well templates for Apache, nginx, postgres, rsync
git clone https://github.com/andrii-suse/environ
sudo make -C environ install
# First choose a slot to use in script, mc0 - mc9 are available, so several instances at the same time
# here we will use slot 1 => mc1, first parameter is where MirrorCache sources are located
mc=$(environ mc ~/github/MirrorCache)
# pg1-system2 will setup local instance of Postgres server with data directory in pg1-system2/dt/
$mc/gen_config MIRRORCACHE_ROOT=http://download.opensuse.org \
     MIRRORCACHE_TOP_FOLDERS="'debug distribution factory history ports repositories source tumbleweed update'" \
    MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb \
    MOJO_REVERSE_PROXY=1

$mc/start

$mc/backstage/start

$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select 'mirror.aarnet.edu.au','/pub/opensuse/opensuse','t','au',''"

# check status
$mc/db/status
$mc/backstage/status
$mc/status
```

### Run tests from [t/environ](/t/environ) with docker, manually for debugging

- Requires docker configured for non-root users
- Available configuration:
  - `MIRRORCACHE_CITY_MMDB` adds this environment variable inside the container and mounts it as a volume if the file exists on the host
  - `EXPOSE_PORT` maps whatever port you need from the container to host port 80
    ```bash
    cd t/environ

    # Just run the test:
    ./01-smoke.sh

    # Run the test with your own MIRRORCACHE_CITY_MMDB
    MIRRORCACHE_CITY_MMDB=/var/lib/GeoIP/GeoLite2-City.mmdb ./01-smoke.sh

    # Run the test and keep the container, while mapping port 3110 to host port 80
    EXPOSE_PORT=3110 ./01-smoke.sh
    ```

    To log in with a fake test-user, change `$mc/start` to `MIRRORCACHE_TEST_TRUST_AUTH=1 $mc/start` in your test

    Setting `MIRRORCACHE_TEST_TRUST_AUTH` to any number > 1 will result in `current_user` being `undef`, so no fake test-user login.
    You will only have access to some routes defined in [lib/MirrorCache/WebAPI.pm](/lib/MirrorCache/WebAPI.pm).

**WARNING** - Be careful when working inside container:
1. The source tree is mapped to the host, so any changes of source code inside container will be reflected on host and vice versa.
2. The container is removed automatically on next test start of the same test, so any modifications outside source tree will be lost.

Don't forget to clean up the test containers when you're done :)
