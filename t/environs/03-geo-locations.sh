#!lib/test-in-container-environs.sh
set -ex

./environ.sh pg9-system2

./environ.sh mc9 $(pwd)/MirrorCache
pg9*/status.sh 2 > /dev/null || pg9*/start.sh

pg9*/create.sh db mc_test
mc9*/configure_db.sh pg9

./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2

export MIRRORCACHE_PEDANTIC=1

for x in mc9 ap7-system2 ap8-system2 ap9-system2; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
    $x/start.sh
done

berlin_host=$(ap9*/print_address.sh)
munich_host=$(ap8*/print_address.sh)
altona_host=$(ap7*/print_address.sh)

declare -A berlin=( [host]=$berlin_host [lat]=52 [lng]=13 )
declare -A munich=( [host]=$munich_host [lat]=48 [lng]=12 )
declare -A altona=( [host]=$altona_host [lat]=53.5 [lng]=9.9 )

declare -a cases=(berlin munich altona)

for case in "${cases[@]}"; do
    declare -n p="$case"
    pg9*/sql.sh -c "insert into server(hostname,urldir,enabled,country,region,lat,lng) select '${p[host]}','','t','de','',${p[lat]},${p[lng]}" mc_test
done

# first request a file, so the mirror scan will trigger on backstage run
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep 200

mc9*/backstage/job.sh folder_sync_schedule_from_misses
mc9*/backstage/job.sh folder_sync_schedule
mc9*/backstage/shoot.sh

# 127.0.0.3 is in Nuremberg, so Munich must be chosen as the closest host
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep -C 10 302 | grep $munich_host

# let's shut down Munich server - now Berlin must be selected as it closer to Nuremberg than Altona
ap8*/stop.sh
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep -C 10 302 | grep $berlin_host

# start Munich back - it must be chosen again
ap8*/start.sh
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat
curl --interface 127.0.0.3 -Is http://127.0.0.1:3190/download/folder1/file1.dat | grep -C 10 302 | grep $munich_host
