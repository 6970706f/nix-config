#!/usr/bin/env bash

ROFI=(rofi -dmenu -i -no-custom -config "$HOME/.config/rofi/utility.rasi")

menu() {
    printf '%s\n' "$@" | "${ROFI[@]}"
}

# ============================================================
# DISPLAY
# ============================================================

display() {
    local choice
    local monitors

    while true; do
        choice=$(menu \
            "󰍹  Monitor Information" \
            "󰍺  Reload Hyprland Config") || return

        case "$choice" in
            *"Monitor Information")
                monitors=$(hyprctl monitors 2>/dev/null)

                printf '%s\n' "$monitors" |
                    "${ROFI[@]}" -p "Displays"
                ;;

            *"Reload Hyprland Config")
                hyprctl reload
                ;;
        esac
    done
}

# ============================================================
# DISKS
# ============================================================

disks() {
    local root_partition
    local root_disk
    local devices
    local selected
    local device

    root_partition=$(findmnt -n -o SOURCE /)
    root_disk=$(lsblk -no PKNAME "$root_partition" 2>/dev/null)

    if [ -n "$root_disk" ]; then
        root_disk="/dev/$root_disk"
    else
        root_disk="$root_partition"
    fi

    while true; do
        devices=$(
            lsblk -e7 \
                -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS \
                -p 2>/dev/null |
            while IFS= read -r line; do
                device=$(printf '%s\n' "$line" |
                    sed -nE 's/.*(\/dev\/[^[:space:]]+).*/\1/p')

                [ -n "$device" ] || {
                    printf '%s\n' "$line"
                    continue
                }

                parent_disk=$(lsblk -no PKNAME "$device" 2>/dev/null)

                if [ "$device" = "$root_disk" ] ||
                    { [ -n "$parent_disk" ] &&
                      [ "/dev/$parent_disk" = "$root_disk" ]; }; then
                    continue
                fi

                if findmnt -rn -S "$device" >/dev/null 2>&1; then
                    status="Mounted"
                else
                    status="Unmounted"
                fi

                printf '%-80s [%s]\n' "$line" "$status"
            done
        )

        selected=$(printf '%s\n' "$devices" |
            "${ROFI[@]}" -p "Disks") || return

        [ -n "$selected" ] || return

        device=$(printf '%s\n' "$selected" |
            sed -nE 's/.*(\/dev\/[^[:space:]]+).*/\1/p')

        [ -b "$device" ] || continue

        if findmnt -rn -S "$device" >/dev/null 2>&1; then
            udisksctl unmount -b "$device" >/dev/null 2>&1
        else
            udisksctl mount -b "$device" >/dev/null 2>&1
        fi
    done
}

# ============================================================
# CLIPBOARD
# ============================================================

clipboard() {
    local selected

    if ! command -v cliphist >/dev/null; then
        rofi -e "cliphist is not installed"
        return
    fi

    selected=$(cliphist list |
        "${ROFI[@]}" -p "Clipboard") || return

    [ -n "$selected" ] || return

    printf '%s\n' "$selected" |
        cliphist decode |
        wl-copy
}

# ============================================================
# COLOR PICKER
# ============================================================

color_picker() {
    if ! command -v hyprpicker >/dev/null; then
        rofi -e "hyprpicker is not installed"
        return
    fi

    color=$(hyprpicker -a)

    [ -n "$color" ] || return

    notify-send "Color Picker" "Copied: $color"
}

# ============================================================
# SCRIPTS
# ============================================================

scripts() {
    local dir="$HOME/.config/hypr/scripts"
    local selected

    while true; do
        mapfile -t files < <(
            find "$dir" \
                -maxdepth 1 \
                -type f \
                -name '*.sh' \
                -printf '%f\n' |
            sort
        )

        [ "${#files[@]}" -gt 0 ] || return

        selected=$(printf '%s\n' "${files[@]}" |
            "${ROFI[@]}" -p "Scripts") || return

        [ -n "$selected" ] || return

        case "$selected" in
            rofi-menu.sh)
                continue
                ;;

            *)
                "$dir/$selected"
                ;;
        esac

        return
    done
}

# ============================================================
# POWER
# ============================================================

power() {
    local choice

    choice=$(menu \
        "󰌾  Lock" \
        "󰒲  Suspend" \
        "󰍃  Log Out" \
        "󰜉  Reboot" \
        "󰐥  Power Off") || return

    case "$choice" in
        *"Lock")
            hyprlock
            ;;

        *"Suspend")
            systemctl suspend
            ;;

        *"Log Out")
            hyprctl dispatch exit
            ;;

        *"Reboot")
            systemctl reboot
            ;;

        *"Power Off")
            systemctl poweroff
            ;;
    esac
}

# ============================================================
# MAIN MENU
# ============================================================

while true; do
    choice=$(menu \
        "󰍹  Display" \
        "󰋊  Disks" \
        "󰋼  Clipboard" \
        "󰄀  Color Picker" \
        "󰒓  Scripts" \
        "󰐥  Power") || exit 0

    case "$choice" in
        *"Display")
            display
            ;;

        *"Disks")
            disks
            ;;

        *"Clipboard")
            clipboard
            ;;

        *"Color Picker")
            color_picker
            ;;

        *"Scripts")
            scripts
            ;;

        *"Power")
            power
            ;;
    esac
done
