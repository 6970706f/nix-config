#!/usr/bin/env bash

SAVE_DIR="$HOME/Pictures/Prints"
mkdir -p "$SAVE_DIR"

OUTPUT="$SAVE_DIR/print_$(date +%Y-%m-%d_%H-%M-%S).png"

AREA=$(slurp) || exit 0

if grim -g "$AREA" - | tee "$OUTPUT" | wl-copy; then
    notify-send "⏺ screenshot" "saved and copied to clipboard"
else
    rm -f "$OUTPUT"
    notify-send "⏹ screenshot" "failed to save or copy screenshot"
    exit 1
fi

