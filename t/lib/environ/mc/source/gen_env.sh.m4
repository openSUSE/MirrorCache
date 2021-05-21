[ -e __workdir/conf.env ] || {
    __workdir/print_env > __workdir/conf.env
    for i in "$@"; do
        [ -z "$i" ] || echo "export $i" >> __workdir/conf.env
    done
}
