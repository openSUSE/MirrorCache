[ -f __workdir/.pid ] || exit 0

kill "$(cat __workdir/.pid)"

# wait ~5 sec, then kill hard
cnt=50
while kill -0 "$(cat __workdir/.pid)" 2>/dev/null && ! ps -p "$(cat __workdir/.pid)" | grep -q defunc ; do
    sleep 0.1
    if [ $((cnt--)) -le 1 ]; then
        kill -9 "$(cat __workdir/.pid)"
        sleep 0.1
        break
    fi
done
