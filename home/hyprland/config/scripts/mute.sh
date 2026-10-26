#!/usr/bin/env bash

MIC="@DEFAULT_AUDIO_SOURCE@"

wpctl set-mute "$MIC" toggle

if wpctl get-volume "$MIC" | grep -q MUTED; then
    paplay --volume=39321 ~/.config/hypr/media/mic-mute.mp3
    notify-send "⏹ microphone" "microphone muted"
else
    paplay --volume=39321 ~/.config/hypr/media/mic-unmute.mp3
    notify-send "⏺ microphone" "microphone unmuted"
fi

pkill -SIGRTMIN+9 waybar

