thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -e

imagetag=mirrorcachesalted
containername=$imagetag
ret=1

function cleanup {
    [ "$in_cleanup" != 1 ] || return
    in_cleanup=1
    if [ "$ret" != 0 ] && [ -n "$PAUSE_ON_FAILURE" ]; then
        read -rsn1 -p"Test failed, press any key to finish";echo
    fi
    [ "$ret" == 0 ] || echo FAIL $basename
    docker stop -t 0 "$containername" >&/dev/null || :
}

# trap cleanup INT TERM EXIT

docker build -t $imagetag -f "$thisdir"/Dockerfile "$thisdir"/..
docker run --privileged --rm --name $containername -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 3000:3000 -p 80:80 $imagetag
docker exec -t $containername salt-call --local state.apply -l debug 'mirrorcache-21*'
docker exec -t $containername salt-call --local state.apply -l debug 'mirrorcache-22*'
docker exec -t $containername salt-call --local state.apply -l debug 'mirrorcache-2*'

ret=0
