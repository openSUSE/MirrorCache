#!lib/test-in-container-environ.sh
set -ex

mc1=$(environ mc $(pwd))
mc2=$(environ mc2 $(pwd))

for x in $mc1; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    echo -n 0123456789 > $x/dt/folder1/file2.1.dat
    $x/start
done

$mc2/gen_env MIRRORCACHE_ROOT=http://$($mc1/print_address)/download
$mc2/start

$mc2/backstage/job folder_sync_schedule_from_misses
$mc2/backstage/job folder_sync_schedule
$mc2/backstage/start


for x in $mc1 $mc2; do
  for pattern in 'P=*2.1*' 'GLOB=*2.1*' 'REGEX=.*2\.1.*'; do
    for extra in '' '&json' '&jsontable'; do
        echo $x $pattern $extra
        $x/curl /download/folder1/?$pattern$extra | grep -o file2.1.dat
        rc=0
        $x/curl /download/folder1/?$pattern$extra | grep -o file1.1.dat || rc=$?
        test $rc -gt 0
    done
  done
done

echo success
