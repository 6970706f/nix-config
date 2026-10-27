#!/usr/bin/env bash

SAVE_DIR="$HOME/Recordings"
mkdir -p "$SAVE_DIR"

OUTPUT="$SAVE_DIR/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PID_FILE="$RUNTIME_DIR/wf-recorder.pid"
STATE_FILE="$RUNTIME_DIR/recording.state"

AUDIO_SOURCE="$(pactl get-default-sink).monitor"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill -SIGINT "$(cat "$PID_FILE")"

    rm -f "$PID_FILE"
    rm -f "$STATE_FILE"

    pkill -SIGRTMIN+8 waybar

    sleep 1

    LAST_FILE=$(find "$SAVE_DIR" -maxdepth 1 -name "*.mp4" -type f | sort | tail -n 1)

    if [ -n "$LAST_FILE" ]; then
        notify-send "⏹ recording save" "$LAST_FILE"
    fi

else
    notify-send "⏺ recording"

    wf-recorder --audio="$AUDIO_SOURCE" -c h264_vaapi -p qp=30 -d /dev/dri/renderD128 -f "$OUTPUT" &

    echo $! > "$PID_FILE"

    touch "$STATE_FILE"

    pkill -SIGRTMIN+8 waybar
fi
