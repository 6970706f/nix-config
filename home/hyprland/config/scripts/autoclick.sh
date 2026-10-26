#!/usr/bin/env bash

PIDFILE="/tmp/autoclick.pid"

if [[ -f "$PIDFILE" ]]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"

    if [[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null; then
        pkill -TERM -P "$PID" 2>/dev/null || true
        kill -TERM "$PID" 2>/dev/null || true
        rm -f "$PIDFILE"
        notify-send "⏹ autoclick" "autoclick disabled"
        exit 0
    fi

    rm -f "$PIDFILE"
fi

echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

notify-send "⏺ autoclick" "autoclick enabled"

while true; do
    ydotool click 0xC0
done

