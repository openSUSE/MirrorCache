#!lib/test-in-container-environ.sh
set -ex

if [ -z "${BASH_SOURCE[0]}" ]; then
    thisdir=t/environ
else
    thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
fi

rs=$(environ rs)
$rs/configure_dir a $rs/a
$rs/configure_dir longname-with:special $rs/longname-with:special

mkdir -p $rs/a
$rs/start
$rs/status
$rs/ls_a

mkdir -p $rs/a/bb/ccc/dddd
echo -n '' > $rs/a/bb/ccc/a1
echo -n '1234' > $rs/a/bb/ccc/a2

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl rsync://$USER:$USER@$($rs/print_address)/a bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl rsync://$USER:$USER@$($rs/print_address) a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address) /a/bb/ccc/ \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address) /a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/a/bb/ /ccc/ \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

( PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/a bb/ccc/a1 2>&1 || : ) \
    | grep -C 100 -i "not a directory" \
    | grep -v "name = a1"

mkdir -p $rs/longname-with:special/123
touch $rs/longname-with:special/special:file.dat
touch $rs/longname-with:special/123/:file.dat
# test rsync works properly
$rs/ls_longname-with:special | grep special:file.dat

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/longname-with:special/ / \
    | grep "name = special:file.dat; size = 0; mod = 4516"


PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/ /longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$($rs/print_address)/ longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

echo PASS $( basename "${BASH_SOURCE[0]}" )
