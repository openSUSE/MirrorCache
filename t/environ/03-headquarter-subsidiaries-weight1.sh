#!lib/test-in-container-environ.sh
set -ex

# environ by number:
# 9 - headquarter
# 5 - NA subsidiary weight 2
# 6 - NA subsidiary weight 1
# 7 - EU subsidiary
# 8 - ASIA subsidiary

for i in 5 6 7 8 9; do
    x=$(environ mc$i $(pwd))
    mkdir -p $x/dt/{folder1,folder2,folder3}
    echo $x/dt/{folder1,folder2,folder3}/{file1.1,file2.1}.dat | xargs -n 1 touch
    eval mc$i=$x
done

hq_address=$($mc9/print_address)
na_address1=$($mc5/print_address)
na_address2=$($mc6/print_address)
na_interface=127.0.0.2
eu_address=$($mc7/print_address)
eu_interface=127.0.0.3
as_address=$($mc8/print_address)
as_interface=127.0.0.4

# deploy db
$mc9/gen_env MIRRORCACHE_TOP_FOLDERS='folder1 folder2 folder3'
$mc9/backstage/shoot

$mc9/sql "insert into subsidiary(hostname,region,weight) select '$na_address1','na',1"
$mc9/sql "insert into subsidiary(hostname,region,weight) select '$na_address2','na',3"
$mc9/sql "insert into subsidiary(hostname,region,weight) select '','na',2"
$mc9/sql "insert into subsidiary(hostname,region) select '$eu_address','eu'"
$mc9/sql "insert into subsidiary(hostname,region) select '$as_address','as'"

$mc9/start
$mc5/gen_env MIRRORCACHE_REGION=na
$mc5/start
$mc6/gen_env MIRRORCACHE_REGION=na
$mc6/start
$mc7/gen_env MIRRORCACHE_REGION=eu
$mc7/start
$mc8/gen_env MIRRORCACHE_REGION=as
$mc8/start

echo the root folder is not redirected
curl --interface $eu_interface -Is http://$hq_address/ | grep '200 OK'

echo check redirection from headquarter
curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.1.dat
curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.1.dat | grep -E "(Location: http:\/\/($na_address1|$na_address2)\/download\/folder1\/file1.1.dat)|(200 OK)"


# do requests and check that both na instances are being used and instance 2 is used more frequently
out=$(
counter=180

while test $counter -gt 0
do
    curl --interface $na_interface -Is http://$hq_address/download/folder1/file1.1.dat
    ((counter--))
done
)

out1=$(echo "$out" | grep "Location: http://$na_address1/download/folder1/file1.1.dat" | wc -l)
out2=$(echo "$out" | grep "Location: http://$na_address2/download/folder1/file1.1.dat" | wc -l)
out3=$(echo "$out" | grep "200 OK" | wc -l)

test $out1 -gt 0
test $out2 -gt 0
test $out3 -gt 0
test $out2 -gt $out1
test $out2 -gt $out3
test $out3 -gt $out1

