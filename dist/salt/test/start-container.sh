thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -ex

imagetag=mirrorcachesalted
containername=$imagetag

podman_info="$(podman info >/dev/null 2>&1)" || {
    echo "Podman doesn't seem to be available"
    (exit 1)
}

(
if test "$MIRRORCACHE_OPTIMIZED_BUILD" == 1; then
    sed 's/^# optimization //' "$thisdir"/Dockerfile
else
    cat "$thisdir"/Dockerfile
fi
) | podman build -t $imagetag -f - "$thisdir"/..

if podman ps | grep $containername ; then
    echo Stopping running container $container...
    podman stop -t0 $containername
    sleep 1
fi

podman run --rm --name $containername -d -p 3000:3000 $imagetag
podman exec $containername mkdir -p /var/lib/GeoIP/
podman cp $thisdir/../../../t/data/city.mmdb $containername:/var/lib/GeoIP/GeoLite2-City.mmdb
podman exec -t $containername salt-call --local state.apply -l debug mirrorcache.postgres
podman exec -t $containername salt-call --local state.apply -l debug mirrorcache.webui
podman exec -t $containername salt-call --local state.apply -l debug mirrorcache.backstage
podman exec -t $containername sudo -u postgres psql -a -f /opt/mirrors-eu.sql -d mirrorcache
