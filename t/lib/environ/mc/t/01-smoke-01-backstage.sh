set -euo pipefail
mc=$(environ mc $(pwd))

$mc/backstage/start
$mc/backstage/status
$mc/backstage/stop

rc=0
$mc/status 2>/dev/null || rc=$?

test $rc -gt 0
echo PASS $0
