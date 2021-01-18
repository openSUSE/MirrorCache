thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -e

imagetag=mirrorcachesalted
containername=$imagetag

test "${PRIVILEGED_TESTS}" == 1 || {
   echo PRIVILEGED_TESTS is not set to 1
   (exit 1)
}
docker_info="$(docker info >/dev/null 2>&1)" || { 
    echo "Docker doesn't seem to be running"
    (exit 1)
}

docker build -t $imagetag -f "$thisdir"/Dockerfile "$thisdir"/..
docker run --privileged --rm --name $containername -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 3000:3000 -p 80:80 $imagetag
docker exec -t $containername salt-call --local state.apply -l debug 'role/mirrorcache-eu'
