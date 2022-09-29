#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

ap9=$(environ ap9)
ap8=$(environ ap8)
ap7=$(environ ap7)

for x in $mc $ap7 $ap8 $ap9; do
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    $x/start
done

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.2:1304','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.3:1314','','t','de','eu'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '127.0.0.4:1324','','t','cn','as'"

$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat | grep 200
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat

$mc/backstage/job folder_sync_schedule_from_misses
$mc/backstage/job folder_sync_schedule
$mc/backstage/shoot
$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

# check unknown country
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat?COUNTRY=xx
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat?COUNTRY=xx | grep -C10 302 | grep -E '1304|1314|1324'
$mc/curl --interface 127.0.0.4 -i /download/folder1/file1.1.dat.mirrorlist?COUNTRY=xx | grep -C10 1304 | grep -C10 1314| grep 1324

# check country routing
$mc/curl --interface 127.0.0.4 -I /download/folder1/file1.1.dat | grep 1324
$mc/curl --interface 127.0.0.3 -I /download/folder1/file1.1.dat | grep 1314
$mc/curl --interface 127.0.0.2 -I /download/folder1/file1.1.dat | grep 1304
$mc/curl -I /download/folder1/file1.1.dat?IP=127.0.0.4 | grep 1324
$mc/curl -I /download/folder1/file1.1.dat?IP=127.0.0.3 | grep 1314
$mc/curl -I /download/folder1/file1.1.dat?IP=127.0.0.2 | grep 1304

# check same continent
$mc/curl --interface 127.0.0.4 -Is /download/folder1/file1.1.dat?COUNTRY=jp | grep 1324
$mc/curl --interface 127.0.0.3 -Is /download/folder1/file1.1.dat?COUNTRY=jp | grep 1324
$mc/curl --interface 127.0.0.2 -Is /download/folder1/file1.1.dat?COUNTRY=jp | grep 1324

$mc/curl --interface 127.0.0.4 -Is /download/folder1/file1.1.dat?COUNTRY=it | grep 1314
$mc/curl --interface 127.0.0.3 -Is /download/folder1/file1.1.dat?COUNTRY=it | grep 1314
$mc/curl --interface 127.0.0.2 -Is /download/folder1/file1.1.dat?COUNTRY=it | grep 1314

$mc/curl --interface 127.0.0.4 -Is /download/folder1/file1.1.dat?COUNTRY=ca | grep 1304
$mc/curl --interface 127.0.0.3 -Is /download/folder1/file1.1.dat?COUNTRY=ca | grep 1304
$mc/curl --interface 127.0.0.2 -Is /download/folder1/file1.1.dat?COUNTRY=ca | grep 1304

# Further we test that servers are listed only once in metalink output
$mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 /download/folder1/file1.1.dat

duplicates=$($mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 /download/folder1/file1.1.dat | grep location | grep -E -o 'https?[^"s][^\<]*' | sort | uniq -cd | wc -l)
test 0 == "$duplicates"

$mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s /download/folder1/file1.1.dat | grep -B20 127.0.0.2 |  grep -i 'this country (us)'

# test get parameter COUNTRY
$mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s /download/folder1/file1.1.dat?COUNTRY=DE | grep -B20 127.0.0.3 | grep -i 'this country (de)'

# test get parameter AVOID_COUNTRY
$mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s /download/folder1/file1.1.dat?AVOID_COUNTRY=DE,US | grep 127.0.0.4

# check continent
$mc/curl -H "Accept: */*, application/metalink+xml" --interface 127.0.0.2 -s /download/folder1/file1.1.dat?COUNTRY=fr | grep -B20 127.0.0.3
$mc/curl -H "Accept: */*, application/metalink4+xml" --interface 127.0.0.2 -s /download/folder1/file1.1.dat?COUNTRY=fr | grep -B20 127.0.0.3
