-- ####################
-- ### AUTOSTART
-- ####################

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprlock & waybar & hypridle & awww-daemon &")
    hl.exec_cmd("wl-paste --watch cliphist store")
end)
