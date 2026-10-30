--####################
--### GERAL
--####################

hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 4,

        border_size = 0,

        col = {
            active_border   = "rgba(595959aa)",
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    --####################
    --### DECORAÇÃO
    --####################

    decoration = {
        rounding       = 7,
        rounding_power = 10,

        active_opacity   = 1,
        inactive_opacity = 1,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled          = false,
            xray             = false,
            special          = false,
            ignore_opacity   = false, -- Allows opacity blurring
            new_optimizations = true,
            popups           = true,
            input_methods    = true,
            size             = 8,
            passes           = 2,
        },
    },

    --####################
    --### ANIMAÇÕES
    --####################

    animations = {
        enabled = false,
    },

    --####################
    --### LAYOUTS
    --####################

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    --####################
    --### MISC
    --####################

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = true,
    },
})

hl.curve("default", {
    type = "bezier",
    points = { { 0.12, 0.92 }, { 0.08, 1.0 } },
})

hl.curve("wind", {
    type = "bezier",
    points = { { 0.12, 0.92 }, { 0.08, 1.0 } },
})

hl.curve("overshot", {
    type = "bezier",
    points = { { 0.18, 0.95 }, { 0.22, 1.03 } },
})

hl.curve("liner", {
    type = "bezier",
    points = { { 1, 1 }, { 1, 1 } },
})

hl.animation({ leaf = "windows",     enabled = true, speed = 5,  bezier = "wind",     style = "popin 60%" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 6,  bezier = "overshot", style = "popin 60%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4,  bezier = "overshot", style = "popin 60%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4,  bezier = "overshot", style = "slide" })
hl.animation({ leaf = "layers",      enabled = true, speed = 4,  bezier = "default",  style = "popin" })
hl.animation({ leaf = "fadeIn",      enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "fadeOut",     enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "fadeSwitch",  enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "fadeShadow",  enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "fadeDim",     enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "fadeLayers",  enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 5,  bezier = "overshot", style = "slidevert" })
hl.animation({ leaf = "border",      enabled = true, speed = 1,  bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 24, bezier = "liner",    style = "loop" })
