#!lib/test-in-container-environs.sh
set -ex

thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

./environ.sh rs9-system2

rs9*/configure_dir.sh a "$(pwd)"/rs9-system2/a
rs9*/configure_dir.sh longname-with:special "$(pwd)"/rs9-system2/longname-with:special

mkdir -p rs9-system2/a
rs9*/start.sh
rs9*/status.sh
rs9*/ls_a.sh

if [ -z "${BASH_SOURCE[0]}" ]; then
    thisdir=MirrorCache/t/environs
else
    thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
fi

mkdir -p rs9-system2/a/bb/ccc/dddd
echo -n '' > rs9-system2/a/bb/ccc/a1
echo -n '1234' > rs9-system2/a/bb/ccc/a2

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl rsync://$USER:$USER@$(rs9-system2/print_address.sh)/a bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl rsync://$USER:$USER@$(rs9-system2/print_address.sh) a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh) /a/bb/ccc/ \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh) /a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/a/bb/ccc \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/a/bb/ /ccc/ \
    | grep -C 100 "name = dddd; size = 4096; mod = 493" \
    | grep -C 100 "name = a1; size = 0; mod = 4516" \
    | grep -C 100 "name = a2; size = 4; mod = 4516"

( PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/a bb/ccc/a1 2>&1 || : ) \
    | grep -C 100 -i "not a directory" \
    | grep -v "name = a1"

mkdir -p rs9-system2/longname-with:special/123
touch rs9-system2/longname-with:special/special:file.dat
touch rs9-system2/longname-with:special/123/:file.dat
# test rsync works properly
rs9*/ls_longname-with:special.sh | grep special:file.dat

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/longname-with:special/ / \
    | grep "name = special:file.dat; size = 0; mod = 4516"


PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/ /longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

PERL5LIB="$thisdir"/../../lib perl $thisdir/lib/file-listing-rsync-init.pl $USER:$USER@$(rs9-system2/print_address.sh)/ longname-with:special/123 \
    | grep "name = :file.dat; size = 0; mod = 4516"

echo PASS $( basename "${BASH_SOURCE[0]}" )
