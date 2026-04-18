#!/bin/sh
# VCD Sidecar entrypoint — runs inotify watcher and NetworkPolicy sync in parallel

set -e

/usr/local/bin/watch.sh &
WATCH_PID=$!

/usr/local/bin/sync_netpol.sh &
SYNC_PID=$!

# Exit if either subprocess dies
wait -n $WATCH_PID $SYNC_PID
