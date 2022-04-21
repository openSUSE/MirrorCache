#!lib/test-in-container-environ.sh
set -ex

mc=$(environ mc $(pwd))

$mc/start

ap8=$(environ ap8)
ap7=$(environ ap7)

$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap7/print_address)','','t','us','na'"
$mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($ap8/print_address)','','t','us','eu'"

$mc/curl /rest/server | grep $($ap7/print_address) | grep $($ap8/print_address)

$mc/curl /rest/myip --interface 127.0.0.3
$mc/curl /rest/myip --interface 127.0.0.3 | grep -C10 -i '\bDE\b' | grep -i '\bEU\b'

