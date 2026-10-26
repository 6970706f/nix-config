#!/usr/bin/env bash

SAVE_DIR="$HOME/Pictures/Prints"
mkdir -p "$SAVE_DIR"
OUTPUT="$SAVE_DIR/print_$(date +%Y-%m-%d_%H-%M-%S).png"

AREA=$(slurp) || exit 0
grim -g "$AREA" - | tee "$OUTPUT" | wl-copy
