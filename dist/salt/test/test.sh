set -ex
curl -si 127.0.0.1:3000/rest/server || echo "return_code=$?"
curl -s 127.0.0.1:3000/rest/server | grep -o mirror.23media.com

podman exec mirrorcachesalted curl --interface 127.0.0.3 -s 127.0.0.1:3000/download | grep repositories
podman exec mirrorcachesalted curl --interface 127.0.0.3 -sL 127.0.0.1:3000/repositories | grep '<tr>'

podman exec mirrorcachesalted journalctl -xn200 --no-pager -u mirrorcache
podman exec mirrorcachesalted salt-call --local state.apply -l debug mirrorcache.webui
podman exec mirrorcachesalted salt-call --local state.apply -l debug mirrorcache.backstage
