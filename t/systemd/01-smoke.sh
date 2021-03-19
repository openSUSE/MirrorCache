#!../lib/test-in-container-systemd.sh

set -ex

make install
echo MIRRORCACHE_ROOT=/srv/mirrorcache > /usr/share/mirrorcache/conf.env
make setup_production_assets
make setup_system_user

mkdir -p /srv/mirrorcache
touch /srv/mirrorcache/test1

systemctl start postgresql
systemctl is-active --quiet postgresql || systemctl is-active postgresql

make setup_system_db

systemctl start mirrorcache
systemctl is-active --quiet mirrorcache || systemctl is-active mirrorcache

sleep 1
curl -s 127.0.0.1:3000/download | grep test1 || systemctl status mirrorcache
sleep 1
curl -s 127.0.0.1:3000/download | grep test1

systemctl start mirrorcache-backstage
systemctl is-active --quiet mirrorcache || systemctl is-active mirrorcache
systemctl is-active --quiet mirrorcache-backstage || systemctl is-active mirrorcache-backstage

systemctl stop mirrorcache
echo 'MOJO_LISTEN=http://*:8000' >> /usr/share/mirrorcache/conf.env
systemctl start mirrorcache
systemctl is-active --quiet mirrorcache || systemctl is-active mirrorcache

sleep 1
curl -s 127.0.0.1:8000/download | grep test1 || systemctl status mirrorcache
sleep 1
curl -s 127.0.0.1:8000/download | grep test1
