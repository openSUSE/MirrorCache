#!/bin/bash
#
# Copyright (C) 2020,2023 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

initscript=$1
testcase=$2

[ -n "$testcase" ] || {
  testcase=$initscript
  initscript=""
}

[ -n "$testcase" ] || {
  echo "No testcase provided"
  exit 1
}

: "${MIRRORCACHE_DB_PROVIDER:=postgresql}"

set -eo pipefail

[ -n "$testcase" ] || (echo No testcase provided; exit 1) >&2
[ -f "$testcase" ] || (echo Cannot find file "$testcase"; exit 1 ) >&2

thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
basename=$(basename "$testcase")
basename=${basename,,}
basename=${basename//:/_}
ident=mc.systemdtest
containername="$ident.${basename,,}"
PODMAN=podman
podman_info="$($PODMAN info >/dev/null 2>&1)" || {
    echo "{$PODMAN} info returned error ($?)"
    (exit 1)
}

mkdir -p $thisdir/src
cp $thisdir/../data/city.mmdb $thisdir/src/

$PODMAN build --net=host -t $ident.image -f $thisdir/Dockerfile.systemd.$MIRRORCACHE_DB_PROVIDER $thisdir

map_port=""
[ -z "$EXPOSE_PORT" ] || map_port="-p $EXPOSE_PORT:80"
$PODMAN run --net=host --privileged $map_port --rm --name "$containername" -d -v"$thisdir/../..":/opt/project -e MIRRORCACHE_DB_PROVIDER=$MIRRORCACHE_DB_PROVIDER -- $ident.image

in_cleanup=0

ret=111

function cleanup {
    [ "$in_cleanup" != 1 ] || return
    in_cleanup=1
    if [ "$ret" != 0 ] && [ -n "${T_PAUSE_ON_FAILURE-}" ]; then
        read -rsn1 -p"Test failed, press any key to finish";echo
    fi
    [ "$ret" == 0 ] || echo FAIL $basename
    $PODMAN stop -t 0 "$containername" >&/dev/null || :
}

trap cleanup INT TERM EXIT
counter=1

# wait container start
until [ $counter -gt 10 ]; do
  sleep 0.5
  $PODMAN exec "$containername" pwd >& /dev/null && break
  ((counter++))
done

$PODMAN exec "$containername" pwd >& /dev/null || (echo Cannot start container; exit 1 ) >&2

echo "$*"
# [ -z $initscript ] || echo "bash -xe /opt/project/t/docker/$initscript" | $PODMAN exec -i "$containername" bash -x

set +e
$PODMAN exec -e TESTCASE="$testcase"  -i "$containername" bash < "$testcase"
ret=$?
( exit $ret )
