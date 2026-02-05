#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start

ru=$(environ ap6)
by=$(environ ap7)
de=$(environ ap8)

for x in $mc $ru $by $de; do
    mkdir -p $x/dt/test
    echo "content" > $x/dt/test/file.txt
done

$ru/start
$by/start
$de/start

# Configure mirrors
# ap6 -> ru
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ru/print_address)','','t','ru','eu'"
# ap7 -> by
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($by/print_address)','','t','by','eu'"
# ap8 -> de
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($de/print_address)','','t','de','eu'"

$mc/backstage/job -e folder_sync -a '["/test"]'
$mc/backstage/job -e mirror_scan -a '["/test"]'
$mc/backstage/shoot

# Test 1: Request from UA (sanctioned country)
# Expectation: RU and BY mirrors are avoided. DE mirror is used.
echo "Testing request from UA..."
out=$($mc/curl "/download/test/file.txt.metalink?COUNTRY=ua")

if echo "$out" | grep -q "$($ru/print_address)"; then
    echo "FAIL: UA request got RU mirror"
    exit 1
fi
if echo "$out" | grep -q "$($by/print_address)"; then
    echo "FAIL: UA request got BY mirror"
    exit 1
fi
if ! echo "$out" | grep -q "$($de/print_address)"; then
    echo "FAIL: UA request did not get DE mirror"
    exit 1
fi

# Test 2: Request from DE (sanctioning country)
# Expectation: RU and BY mirrors are avoided.
echo "Testing request from DE..."
out_de=$($mc/curl "/download/test/file.txt.metalink?COUNTRY=de")

if echo "$out_de" | grep -q "$($ru/print_address)"; then
    echo "FAIL: DE request got RU mirror"
    exit 1
fi
if echo "$out_de" | grep -q "$($by/print_address)"; then
    echo "FAIL: DE request got BY mirror"
    exit 1
fi
if ! echo "$out_de" | grep -q "$($de/print_address)"; then
    echo "FAIL: DE request did not get DE mirror"
    exit 1
fi

# Test 3: Request from RU
# Expectation: RU mirror is available.
echo "Testing request from RU..."
out_ru=$($mc/curl "/download/test/file.txt.metalink?COUNTRY=ru")

if ! echo "$out_ru" | grep -q "$($ru/print_address)"; then
    echo "FAIL: RU request did not get RU mirror"
    exit 1
fi

echo "success"