port=__port

# let's expect url in first or last position only
if [[ $1 =~ ^- ]]; then
    curl "${@:1:$#-1}" -s 127.0.0.1:$port"${@: -1}"
else
    curl 127.0.0.1:$port"$@" -s
fi
