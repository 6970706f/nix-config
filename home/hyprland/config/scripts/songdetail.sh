#!/usr/bin/env bash

TRACK="$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null || true)"
if [[ -n "$TRACK" ]]; then
    printf '%s\n' "$TRACK"
else
    printf '%s\n' "No music playing"
fi
