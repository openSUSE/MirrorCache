#!lib/test-in-container-environs.sh
set -ex

thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

./environ.sh rs9-system2

rs9*/configure_dir.sh a "$(pwd)"/rs9-system2/a

mkdir -p rs9-system2/a
rs9*/start.sh
rs9*/status.sh
rs9*/ls_a.sh

mkdir -p rs9-system2/a/bb/ccc/dddd
echo -n '' > rs9-system2/a/bb/ccc/a1
echo -n '1234' > rs9-system2/a/bb/ccc/a2


address=$(rs9-system2/print_address.sh)
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
