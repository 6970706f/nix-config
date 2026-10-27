#!/usr/bin/env bash

PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/autoclick.pid"

is_autoclick() {
    local pid="$1"

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ -r "/proc/$pid/cmdline" ]] || return 1

    tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q 'autoclick\.sh'
}

if [[ -f "$PIDFILE" ]]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"

    if is_autoclick "$PID"; then
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
    sleep 0.01
done
