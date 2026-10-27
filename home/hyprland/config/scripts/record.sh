#!/usr/bin/env bash
set -Eeuo pipefail

SAVE_DIR="$HOME/Recordings"
mkdir -p "$SAVE_DIR"

OUTPUT="$SAVE_DIR/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PID_FILE="$RUNTIME_DIR/wf-recorder.pid"
STATE_FILE="$RUNTIME_DIR/recording.state"

notify_error() {
    notify-send "⏹ recording error" "$1"
}

is_wf_recorder() {
    local pid="$1"
    local process

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1

    process="$(ps -p "$pid" -o comm= 2>/dev/null)" || return 1
    [[ "$process" == "wf-recorder" ]]
}

if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"

    if is_wf_recorder "$PID"; then
        kill -SIGINT "$PID"

        rm -f "$PID_FILE" "$STATE_FILE"

        pkill -SIGRTMIN+8 waybar || true

        sleep 1

        LAST_FILE="$(find "$SAVE_DIR" -maxdepth 1 -type f -name '*.mp4' -printf '%T@ %p\n' |
            sort -nr | head -n 1 | cut -d' ' -f2-)"

        if [[ -n "$LAST_FILE" ]]; then
            notify-send "⏹ recording saved" "$LAST_FILE"
        fi
    else
        rm -f "$PID_FILE" "$STATE_FILE"
        notify_error "PID inválido ou wf-recorder não está em execução."
    fi

else
    AUDIO_SOURCE="$(pactl get-default-sink).monitor" || {
        notify_error "Não foi possível identificar a fonte de áudio."
        exit 1
    }

    wf-recorder \
        --audio="$AUDIO_SOURCE" \
        -c h264_vaapi \
        -p qp=30 \
        -d /dev/dri/renderD128 \
        -f "$OUTPUT" &

    PID=$!
    echo "$PID" > "$PID_FILE"

    sleep 1

    if is_wf_recorder "$PID"; then
        touch "$STATE_FILE"
        notify-send "⏺ recording" "Gravação iniciada."
    else
        rm -f "$PID_FILE" "$STATE_FILE"
        notify_error "Falha ao iniciar a gravação. Verifique o terminal."
        exit 1
    fi

    pkill -SIGRTMIN+8 waybar || true
fi
