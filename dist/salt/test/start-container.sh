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

( 
if test $MIRRORCACHE_OPTIMIZED_BUILD == 1; then
    sed 's/^# optimization //' "$thisdir"/Dockerfile
else
    cat "$thisdir"/Dockerfile
fi 
) | docker build -t $imagetag -f - "$thisdir"/..

docker run --privileged --rm --name $containername -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 3000:3000 $imagetag
docker exec $containername mkdir -p /var/lib/GeoIP/
docker cp $thisdir/../../../t/data/city.mmdb $containername:/var/lib/GeoIP/GeoLite2-City.mmdb
docker exec -t $containername salt-call --local state.apply -l debug 'role/mirrorcache-eu'
