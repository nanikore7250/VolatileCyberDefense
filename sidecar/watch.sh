#!/bin/sh
# VCD Sidecar — inotify watcher
# Monitors forensics.jsonl for new lines and forwards each entry to Redis.
# One-way only: this process never writes back to the app container.

set -eu

FORENSICS_PATH="${FORENSICS_PATH:-/var/vcd/forensics.jsonl}"
REDIS_URL="${REDIS_URL:-redis://localhost:6379}"
REDIS_KEY="vcd:forensics"

log() { echo "[vcd-sidecar] $*"; }

wait_for_file() {
  log "Waiting for forensics file: $FORENSICS_PATH"
  while [ ! -f "$FORENSICS_PATH" ]; do
    sleep 1
  done
  log "File found, starting watch"
}

send_to_redis() {
  line="$1"
  redis-cli -u "$REDIS_URL" RPUSH "$REDIS_KEY" "$line" > /dev/null
  ip=$(echo "$line" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$ip" ]; then
    redis-cli -u "$REDIS_URL" SADD "vcd:blocked_ips" "$ip" > /dev/null
    log "Forwarded forensic entry, blocked IP: $ip"
  fi
}

wait_for_file

# Process any lines already present before inotify starts (handles restart/race)
last_line=$(wc -l < "$FORENSICS_PATH")
if [ "$last_line" -gt 0 ]; then
  tail -n +"1" "$FORENSICS_PATH" | while IFS= read -r line; do
    [ -n "$line" ] && send_to_redis "$line"
  done
fi

inotifywait -m -e modify --format '%e' "$FORENSICS_PATH" 2>/dev/null | while read -r _event; do
  current_line=$(wc -l < "$FORENSICS_PATH")
  if [ "$current_line" -gt "$last_line" ]; then
    # Read only new lines
    tail -n +"$((last_line + 1))" "$FORENSICS_PATH" | while IFS= read -r line; do
      [ -n "$line" ] && send_to_redis "$line"
    done
    last_line=$current_line
  fi
done
