set -e
curl -sI http://127.0.0.1:__port/ | grep -E '200|302' || ( >&2 echo UI is not reachable; exit 1 )
