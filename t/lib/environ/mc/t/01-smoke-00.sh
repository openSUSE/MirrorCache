set -euo pipefail
mc=$(environ mc $(pwd))

$mc/start
$mc/status

$mc/curl -Is / | grep 200
curl -Is $($mc/print_address) | grep 200

$mc/stop

rc=0
$mc/status 2>/dev/null || rc=$?

test $rc -gt 0
echo PASS $0
