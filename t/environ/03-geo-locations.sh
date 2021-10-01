#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))
MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=2

$mc/gen_env MIRRORCACHE_PEDANTIC=1 \
            MIRRORCACHE_SCHEDULE_RETRY_INTERVAL=$MIRRORCACHE_SCHEDULE_RETRY_INTERVAL

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
done

berlin_host=$($ap9/print_address)
munich_host=$($ap8/print_address)
altona_host=$($ap7/print_address)

declare -A berlin=( [host]=$berlin_host [lat]=52 [lng]=13 )
declare -A munich=( [host]=$munich_host [lat]=48 [lng]=12 )
declare -A altona=( [host]=$altona_host [lat]=53.5 [lng]=9.9 )

declare -a cases=(berlin munich altona)

for case in "${cases[@]}"; do
    declare -n p="$case"
    $mc/db/sql "insert into server(hostname,urldir,enabled,country,region,lat,lng) select '${p[host]}','','t','de','eu',${p[lat]},${p[lng]}"
done

# first request a file, so the mirror scan will trigger on backstage run
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep 200

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

# 127.0.0.3 is in Nuremberg, so Munich must be chosen as the closest host
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep -C 10 302 | grep $munich_host

# let's shut down Munich server - now Berlin must be selected as it closer to Nuremberg than Altona
$ap8/stop
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep -C 10 302 | grep $berlin_host

# start Munich back - it must be chosen again
$ap8/start
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep -C 10 302 | grep $munich_host


$mc/curl --interface 127.0.0.15 /rest/myip
$mc/curl --interface 127.0.0.15 /download/folder2/file1.1.dat.mirrorlist

$mc/sql 'select * from stat order by id desc limit 1'
sleep $MIRRORCACHE_SCHEDULE_RETRY_INTERVAL
$mc/backstage/shoot
$mc/curl --interface 127.0.0.15 /download/folder2/file1.1.dat.mirrorlist | grep -C10 $munich_host | grep -C10 $berlin_host | grep -C10 $altona_host | grep http
