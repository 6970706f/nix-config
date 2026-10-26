#!/usr/bin/env bash

mapfile -t SINKS < <(pactl list short sinks | grep -v '\.monitor' | awk '{print $2}')

if [[ ${#SINKS[@]} -lt 2 ]]; then
    notify-send "⏹ audio" "only one output device found" -t 2000
    exit 1
fi

CURRENT=$(pactl get-default-sink)

CURRENT_INDEX=-1
for i in "${!SINKS[@]}"; do
    if [[ "${SINKS[$i]}" == "$CURRENT" ]]; then
        CURRENT_INDEX=$i
        break
    fi
done

NEXT_INDEX=$(( (CURRENT_INDEX + 1) % ${#SINKS[@]} ))
NEXT_SINK="${SINKS[$NEXT_INDEX]}"

if ! pactl set-default-sink "$NEXT_SINK"; then
    notify-send "⏹ audio" "failed to switch output device" -t 2000
    exit 1
fi

pactl list short sink-inputs | awk '{print $1}' | while read -r INPUT; do
    pactl move-sink-input "$INPUT" "$NEXT_SINK"
done

FRIENDLY=$(pactl list sinks | grep -A 20 "Name: $NEXT_SINK" | grep "device.description" | cut -d'"' -f2)
[[ -z "$FRIENDLY" ]] && FRIENDLY="$NEXT_SINK"

notify-send "⏺ audio switched" "${FRIENDLY,,}" -t 2000

