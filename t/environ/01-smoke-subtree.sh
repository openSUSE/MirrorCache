#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start
$mc/status

ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    mkdir -p $x/dt/updates/{f1,f2,f3}
    echo $x/dt/updates/{f1,f2,f3}/{f1.1,f2.1}.dat | xargs -n 1 touch
done

$ap7/start
$ap7/curl /updates/f1/ | grep f1.1.dat

$ap8/start
$ap8/curl /updates/f1/ | grep f1.1.dat


$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/db/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','de','eu'"


mcsub=$mc/sub

$mcsub/gen_env MIRRORCACHE_SUBTREE=/updates
$mcsub/start

$mc/curl -Is /download/updates/f1/f1.1.dat
$mcsub/curl -Is /download/f1/f1.1.dat

$mc/sql_test 0 == "select count(*) from stat where path like '/f1%'"
$mc/sql_test 2 == "select count(*) from stat where path like '/updates/f1%'"

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot

$mc/db/sql "select * from minion_jobs order by id"

$mc/curl /download/updates/f1/ | grep f1.1.dat
$mcsub/curl /download/f1/ | grep f1.1.dat

# check redirect is correct
$mc/curl -Is /download/updates/f1 | grep -i 'Location: /download/updates/f1/'
$mcsub/curl -Is /download/f1 | grep -i 'Location: /download/f1/'

# only ap7 is in US
$mc/curl    -Is /download/updates/f1/f1.1.dat | grep -C10 302 | grep "$($ap7/print_address)"
$mcsub/curl -Is /download/f1/f1.1.dat         | grep -C10 302 | grep "$($ap7/print_address)"

###################################
# test files are removed properly
rm $mc/dt/updates/f1/f1.1.dat

# resync the folder
$mc/backstage/job folder_sync_schedule
$mc/backstage/job -e mirror_probe -a '["/updates/f1"]'
$mc/backstage/shoot

if $mc/curl -s /download/updates/f1/ | grep f1.1.dat ; then
    fail f1.1.dat was deleted
fi

if $mcsub/curl -s /download/f1/ | grep f1.1.dat ; then
    fail f.1.dat was deleted
fi

$mc/curl -H "Accept: */*, application/metalink+xml" -s /download/updates/f1/f2.1.dat | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/updates/f1/f2.1.dat</url>'
$mcsub/curl -H "Accept: */*, application/metalink+xml" -s /download/f1/f2.1.dat | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/updates/f1/f2.1.dat</url>'
$mc/curl -s /download/updates/f1/f2.1.dat.metalink | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/updates/f1/f2.1.dat</url>'
$mcsub/curl -s /download/f1/f2.1.dat.metalink | grep '<url type="http" location="US" preference="100">http://127.0.0.1:1304/updates/f1/f2.1.dat</url>'

# test unknown file is rendered with render_local()
$mcsub/curl -IL /download/f2/f2.1.dat | grep -i '200 OK'
