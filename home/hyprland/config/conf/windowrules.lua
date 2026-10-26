-- ####################
-- ### WINDOW RULES
-- ####################

-- Suprime evento de maximizar em todas as janelas
hl.window_rule({
    name = "suppress-maximize-events",
    match = {
        class = ".*",
    },
    suppress_event = "maximize",
})

-- Corrige drag em janelas XWayland sem título/classe
hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_initial_focus = true,
})

-- hyprland-run: abre flutuando no canto inferior esquerdo
hl.window_rule({
    name = "move-hyprland-run",
    match = {
        class = "hyprland-run",
    },
    move = { 20, "monitor_h-120" },
    float = true,
})

hl.window_rule({
    name = "floating-kitty",
    match = {
        class = "^(kitty)$",
    },
    float = true,
    size = { 1000, 700 },
    move = { "(cursor_x-(window_w*0.5))", "(cursor_y-(window_h*0.5))" },
})

hl.window_rule({
    name = "floating-thunar",
    match = {
        class = "^(thunar)$",
    },
    float = true,
    size = { 1000, 700 },
    move = { "(cursor_x-(window_w*0.5))", "(cursor_y-(window_h*0.5))" },
})
