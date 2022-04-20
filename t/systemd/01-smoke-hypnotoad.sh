#!../lib/test-in-container-systemd.sh

set -ex

DB=$MIRRORCACHE_DB_PROVIDER
echo DB=$MIRRORCACHE_DB_PROVIDER

make install
echo MIRRORCACHE_ROOT=/srv/mirrorcache > /etc/mirrorcache/conf.env
make setup_production_assets
make setup_system_user

mkdir -p /srv/mirrorcache
touch /srv/mirrorcache/test1

systemctl start $DB
systemctl is-active --quiet $DB || systemctl is-active $DB

make setup_system_db

systemctl start mirrorcache-hypnotoad
systemctl is-active --quiet mirrorcache-hypnotoad || systemctl is-active mirrorcache-hypnotoad

sleep 1
curl -s 127.0.0.1:8080/download | grep test1 || systemctl status mirrorcache-hypnotoad
sleep 1
curl -s 127.0.0.1:8080/download | grep test1

systemctl is-active --quiet mirrorcache-hypnotoad || systemctl is-active mirrorcache-hypnotoad

systemctl stop mirrorcache-hypnotoad
echo 'MOJO_LISTEN=http://*:8000' >> /etc/mirrorcache/conf.env
systemctl start mirrorcache-hypnotoad
systemctl is-active --quiet mirrorcache-hypnotoad || systemctl is-active mirrorcache-hypnotoad

sleep 1
curl -s 127.0.0.1:8000/download | grep test1 || systemctl status mirrorcache-hypnotoad
sleep 1
curl -s 127.0.0.1:8000/download | grep test1
