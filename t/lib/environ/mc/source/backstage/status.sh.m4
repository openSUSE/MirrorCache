[ -f __workdir/.pid ] || ( echo backstage not started; exit 1 )
( kill -0 $(cat __workdir/.pid) && ! ps -p "$(cat __workdir/.pid)" | grep -q defunc && echo backstage seems running ) || ( echo backstage seems be down; exit 1 )
