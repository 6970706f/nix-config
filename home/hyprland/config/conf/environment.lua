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
    btop = terminal .. " -e btop",
    print = "~/.config/hypr/scripts/print.sh",
    record = "~/.config/hypr/scripts/record.sh",
    muteUnmute = "~/.config/hypr/scripts/mute.sh",

    -- ── AppLauncher ──────────────────────────────────
    appLauncherToggle = "qs ipc call appLauncher toggle",

    -- ── Spotifast (MPRIS / player control) ───────────
    spotifastVolumeUp = "playerctl --player=spotifast volume 0.05+",
    spotifastVolumeDown = "playerctl --player=spotifast volume 0.05-",
    spotifastPrevious = "spotifast previous",
    spotifastNext = "spotifast next",
    spotifastPlayPause = "spotifast play-pause",

    -- ── Teclas de mídia do teclado ───────────────────
    audioVolumeUp = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+",
    audioVolumeDown = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
    audioMuteToggle = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
    microphoneMuteToggle = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
    brightnessUp = "brightnessctl -e4 -n2 set 5%+",
    brightnessDown = "brightnessctl -e4 -n2 set 5%-",
    mediaNext = "playerctl next",
    mediaPlayPause = "playerctl play-pause",
    mediaPrevious = "playerctl previous",

}

return variables

