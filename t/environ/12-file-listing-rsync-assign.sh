#!lib/test-in-container-environ.sh
set -ex

if [ -z "${BASH_SOURCE[0]}" ]; then
    thisdir=t/environ
else
    thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
fi

rs=$(environ rs)

mkdir -p $rs/a
$rs/configure_dir a $rs/a

$rs/start
$rs/status
$rs/ls_a

mkdir -p $rs/a/bb/ccc/dddd
echo -n '' > $rs/a/bb/ccc/a1
echo -n '1234' > $rs/a/bb/ccc/a2


address=$($rs/print_address)
host=${address%%:*}
port=${address##*:}

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-assign.pl "$host" "$port" "$USER" "$USER" a bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-assign.pl "$host" "$port" "$USER" "$USER" '' a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-assign.pl "$host" "$port" "$USER" "$USER" '' /a/bb/ccc/ \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

( PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-assign.pl "$host" "$port" "$USER" "$USER" /a/bb/ ccc 2>&1 ) \
    | grep -C100 -i 'unknown module' \
    | grep -qv "name = "


( PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-assign.pl "$host" "$port" "$USER" incorrect a bb/ccc 2>&1 ) \
    | grep -C100 -i error \
    | grep -qv "name = "

echo PASS $( basename "${BASH_SOURCE[0]}" )
