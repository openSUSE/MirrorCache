set -e
[ -e __workdir/conf.env ] || (

    cat __workdir/../conf.env

    echo export MOJO_LISTEN=http://*:$((__port + 1))
    for i in "$@"; do
        [ -z "$i" ] || echo "export $i"
    done
) > __workdir/conf.env
