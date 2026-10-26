#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
CACHE_FILE="$HOME/.cache/awww-index"

if ! pgrep -x awww-daemon > /dev/null; then
    awww-daemon &
    sleep 1
fi

mapfile -t WALLS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | sort)

TOTAL=${#WALLS[@]}

if [[ $TOTAL -eq 0 ]]; then
    notify-send "awww" "Nenhuma imagem encontrada em $WALLPAPER_DIR"
    exit 1
fi

INDEX=$(cat "$CACHE_FILE" 2>/dev/null || echo -1)
INDEX=$(( (INDEX + 1) % TOTAL ))
echo "$INDEX" > "$CACHE_FILE"

CURRENT="${WALLS[$INDEX]}"
NAME=$(basename "$CURRENT")

awww img "$CURRENT" --transition-type grow --transition-fps 144 --transition-pos "$(shuf -i 0-3439 -n 1),$(shuf -i 0-1399 -n 1)"
notify-send "Wallpaper" "$NAME  ($((INDEX + 1))/$TOTAL)"
