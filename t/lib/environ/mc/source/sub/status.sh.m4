curl -sI http://127.0.0.1:$((__port + 1))/ | grep -E '200|302' || ( >&2 echo subtree UI is not reachable; exit 1 )
