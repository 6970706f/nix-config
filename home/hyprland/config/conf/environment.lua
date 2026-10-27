-- ##########################
-- ### ENVIRONMENT VARIABLES
-- ##########################

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

local home = os.getenv("HOME") or ""
local xdgDataDirs = os.getenv("XDG_DATA_DIRS") or ""
hl.env(
    "XDG_DATA_DIRS",
    home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:" .. xdgDataDirs
)

-- ####################
-- ### PROGRAMS
-- ####################

-- ── Apps ──────────────────────────────────────────
local terminal = "kitty"
local browser = "librewolf"

local variables = {
    terminal = terminal,
    fileManager = "thunar",
    mainMod = "SUPER",
    code = "code",
    browser = browser,
    allApps = "vesktop & " .. browser .. " & spotifast",
    autoClick = "~/.config/hypr/scripts/autoclick.sh",

    -- ── Janelas ───────────────────────────────────────
    kill = "killactive",
    fullscreen = "fullscreen, 0",
    floating = "togglefloating",
    altTab = "cyclenext",

    -- ── Sistema ───────────────────────────────────────
    lock = "hyprlock",
    wallpaper = "~/.config/hypr/scripts/nextwallpaper.sh",
    btop = terminal .. " -e btop",
    print = "~/.config/hypr/scripts/print.sh",
    record = "~/.config/hypr/scripts/record.sh",
    muteUnmute = "~/.config/hypr/scripts/mute.sh",

    -- ── Volume (SUPER + setas) ────────────────────────
    soundUp = "pactl set-sink-volume @DEFAULT_SINK@ +5%",
    soundDown = "pactl set-sink-volume @DEFAULT_SINK@ -5%",
    changeSoundOutput = "~/.config/hypr/scripts/toggleaudio.sh",
}

return variables

