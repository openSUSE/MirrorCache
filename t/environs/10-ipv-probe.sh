#!lib/test-in-container-environs.sh

# TODO: THIS TEST REQUIRES IPv6 enabled in DOCKER !!!

# Smoke test for https-only mirrors
set -ex

./environ.sh pg9-system2
# git clone https://github.com/andrii-suse/MirrorCache || :

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
pg9*/sql.sh -f $(pwd)/MirrorCache/sql/schema.sql mc_test

mc9*/configure_db.sh pg9

# mc9 should listen both ipv4 and ipv6
sed -i 's,MOJO_LISTEN=http://127.0.0.1:,MOJO_LISTEN=http://[::]:,' mc9*/start.sh
mc9*/start.sh
mc9*/status.sh
# this mirror will do only ipv6 ::1
./environ.sh ap8-system2
sed -i 's/Listen 1314/Listen [::1]:1314/' ap8-system2/httpd.conf
# this mirror will do only ipv4 127.0.0.1
./environ.sh ap7-system2

for x in mc9 ap7-system2 ap8-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap7*/start.sh
ap8*/start.sh

pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.1:1304','','t','us',''" mc_test 
pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region) select '[::1]:1314','','t','us',''" mc_test

mc9*/backstage/job.sh -e mirror_probe -a '["us"]'
mc9*/backstage/shoot.sh
test t == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=1 and capability='ipv4'" mc_test)
test f == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=1 and capability='ipv6'" mc_test)
test f == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=2 and capability='ipv4'" mc_test)
test t == $(pg9*/sql.sh -t -c "select success from server_capability_check where server_id=2 and capability='ipv6'" mc_test)

# now explicitly force disable corresponding capabilities
pg9*/sql.sh -t -c "insert into server_capability_force(server_id,capability,dt) select 1,'ipv6',now();" mc_test
pg9*/sql.sh -t -c "insert into server_capability_force(server_id,capability,dt) select 2,'ipv4',now();" mc_test

curl -I 127.0.0.1:3190/download/folder1/file1.dat # access file to schedule jobs

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

# make sure it redirects to ipv4 and ipv6 as requested
curl -I -s 127.0.0.1:3190/download/folder1/file1.dat | grep $(ap7*/print_address.sh)
curl -I -s [::1]:3190/download/folder1/file1.dat | grep Location | grep ::1
