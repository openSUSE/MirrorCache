#!../lib/test-in-container-systemd.sh

set -ex

make install
echo MIRRORCACHE_ROOT=/srv/mirrorcache > /etc/mirrorcache/conf.env
echo MIRRORCACHE_ROOT=/srv/mirrorcache > /etc/mirrorcache/conf-subtree.env
echo MIRRORCACHE_SUBTREE=/test1       >> /etc/mirrorcache/conf-subtree.env
make setup_production_assets
make setup_system_user

mkdir -p /srv/mirrorcache
mkdir /srv/mirrorcache/test1
touch /srv/mirrorcache/test1/file1.txt

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


systemctl is-active --quiet mirrorcache-subtree || systemctl is-active mirrorcache-subtree  || journalctl -u mirrorcache-subtree || systemctl status mirrorcache-subtree

systemctl start mirrorcache-subtree

systemctl stop mirrorcache
systemctl stop mirrorcache-subtree
echo 'MOJO_LISTEN=http://*:8000' >> /etc/mirrorcache/conf.env
echo 'MOJO_LISTEN=http://*:8001' >> /etc/mirrorcache/conf-subtree.env
systemctl start mirrorcache
systemctl start mirrorcache-subtree
systemctl is-active --quiet mirrorcache || systemctl is-active mirrorcache
systemctl is-active --quiet mirrorcache-subtree || systemctl is-active mirrorcache-subtree || journalctl -u mirrorcache-subtree || systemctl status mirrorcache-subtree

sleep 1
curl -s 127.0.0.1:8000/download | grep test1 || systemctl status mirrorcache
sleep 1
curl -s 127.0.0.1:8000/download | grep test1

curl -s 127.0.0.1:8001/download | grep file1.txt
