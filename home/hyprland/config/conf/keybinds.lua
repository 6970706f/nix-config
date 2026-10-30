-- ####################
-- ### KEYBINDS
-- ####################

local vars = require("conf.environment")

-- AppLauncher: observa o pressionamento físico de Super e espera pela soltura.
-- Isso evita depender de bind de soltura de modificador, que falha em algumas
-- versões do Hyprland 0.56.x. As combinações Super existentes marcam o gesto
-- como usado, então o launcher não abre depois de Super+1/E/Q etc.
local appLauncherComboUsed = false
local appLauncherTapGeneration = 0
local appLauncherTapTimer = nil
local canPollKeyState = type(hl.is_key_down) == "function"

local function bindSuper(keys, dispatcher, options)
    if not canPollKeyState then
        return hl.bind(keys, dispatcher, options)
    end

    return hl.bind(keys, function()
        appLauncherComboUsed = true
        hl.dispatch(dispatcher)
    end, options)
end

local function toggleAppLauncher()
    hl.dispatch(hl.dsp.exec_cmd(vars.appLauncherToggle))
end

if canPollKeyState then
    -- A detecção por estado também cancela combinações que ainda não têm um
    -- atalho próprio. Os atalhos já definidos continuam usando bindSuper abaixo.
    local watchedKeysyms = {}
    for key in string.gmatch("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", ".") do
        table.insert(watchedKeysyms, key)
    end
    for index = 1, 35 do
        table.insert(watchedKeysyms, "F" .. index)
    end
    for index = 0, 9 do
        table.insert(watchedKeysyms, "KP_" .. index)
    end
    for _, key in ipairs({
        "Escape", "Tab", "space", "Return", "BackSpace", "Delete", "Insert",
        "Home", "End", "Page_Up", "Page_Down", "Left", "Right", "Up", "Down",
        "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R",
        "Meta_L", "Meta_R", "Caps_Lock", "Num_Lock", "Scroll_Lock", "Print",
        "Pause", "Menu", "Help", "comma", "period", "slash", "semicolon",
        "apostrophe", "bracketleft", "bracketright", "backslash", "grave", "minus",
        "equal", "plus", "less", "greater", "question", "quotedbl", "braceleft",
        "braceright", "bar", "colon", "underscore", "asciitilde", "exclam", "at",
        "numbersign", "dollar", "percent", "asciicircum", "ampersand", "asterisk",
        "parenleft", "parenright", "KP_Enter", "KP_Add", "KP_Subtract", "KP_Multiply",
        "KP_Divide", "KP_Decimal", "ISO_Level3_Shift", "Mode_switch",
        "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
        "XF86AudioMicMute", "XF86AudioNext", "XF86AudioPrev", "XF86AudioPlay",
        "XF86AudioPause", "XF86MonBrightnessUp", "XF86MonBrightnessDown",
    }) do
        table.insert(watchedKeysyms, key)
    end

    local function anyNonSuperKeyDown()
        for _, key in ipairs(watchedKeysyms) do
            local ok, isDown = pcall(hl.is_key_down, key)
            if ok and isDown then
                return true
            end
        end
        return false
    end

    local function beginSuperTap()
        appLauncherTapGeneration = appLauncherTapGeneration + 1
        local generation = appLauncherTapGeneration
        appLauncherComboUsed = false

        local function waitForSuperRelease()
            if generation ~= appLauncherTapGeneration then
                return
            end

            if anyNonSuperKeyDown() then
                appLauncherComboUsed = true
            end

            if hl.is_key_down("Super_L") or hl.is_key_down("Super_R") then
                appLauncherTapTimer = hl.timer(waitForSuperRelease, {
                    timeout = 10,
                    type = "oneshot",
                })
                return
            end

            appLauncherTapTimer = nil
            if not appLauncherComboUsed then
                toggleAppLauncher()
            end
            appLauncherComboUsed = false
        end

        appLauncherTapTimer = hl.timer(waitForSuperRelease, {
            timeout = 10,
            type = "oneshot",
        })
    end

    -- Press-only listeners are non-consuming: Super continua funcionando como
    -- modificador para os bindings abaixo. A soltura é detectada por is_key_down.
    hl.bind("Super_L", beginSuperTap, { non_consuming = true })
    hl.bind("Super_R", beginSuperTap, { non_consuming = true })
else
    -- Fallback para versões sem hl.is_key_down.
    hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(vars.appLauncherToggle), { release = true })
    hl.bind("SUPER + SUPER_R", hl.dsp.exec_cmd(vars.appLauncherToggle), { release = true })
end

-- ── Apps ──────────────────────────────────────────
bindSuper(vars.mainMod .. " + Q", hl.dsp.exec_cmd(vars.terminal))
bindSuper(vars.mainMod .. " + E", hl.dsp.exec_cmd(vars.fileManager))
bindSuper(vars.mainMod .. " + C", hl.dsp.exec_cmd(vars.code))
bindSuper(vars.mainMod .. " + B", hl.dsp.exec_cmd(vars.browser))
bindSuper(vars.mainMod .. " + P", hl.dsp.exec_cmd(vars.allApps))
bindSuper(vars.mainMod .. " + F5", hl.dsp.exec_cmd(vars.autoClick))

-- ── Janelas ───────────────────────────────────────
bindSuper(vars.mainMod .. " + W", hl.dsp.window.close())
bindSuper(vars.mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
bindSuper(vars.mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())

-- ── Sistema ───────────────────────────────────────
bindSuper(vars.mainMod .. " + L", hl.dsp.exec_cmd(vars.lock))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(vars.btop))
bindSuper(vars.mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(vars.print))
bindSuper(vars.mainMod .. " + SHIFT + D", hl.dsp.exec_cmd(vars.record))

-- ── Spotifast (SUPER + setas / espaço) ─────────────────────
bindSuper(vars.mainMod .. " + Up", hl.dsp.exec_cmd(vars.spotifastVolumeUp))
bindSuper(vars.mainMod .. " + Down", hl.dsp.exec_cmd(vars.spotifastVolumeDown))
bindSuper(vars.mainMod .. " + Left", hl.dsp.exec_cmd(vars.spotifastPrevious))
bindSuper(vars.mainMod .. " + Right", hl.dsp.exec_cmd(vars.spotifastNext))
bindSuper(vars.mainMod .. " + space", hl.dsp.exec_cmd(vars.spotifastPlayPause))

bindSuper(vars.mainMod .. " + Delete", hl.dsp.exec_cmd(vars.muteUnmute))

-- ── Teclas de mídia (teclado) ─────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(vars.audioVolumeUp), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(vars.audioVolumeDown), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(vars.audioMuteToggle), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(vars.microphoneMuteToggle), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(vars.brightnessUp), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(vars.brightnessDown), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd(vars.mediaNext), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(vars.mediaPlayPause), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(vars.mediaPlayPause), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(vars.mediaPrevious), { locked = true })

-- ── Workspaces ────────────────────────────────────
bindSuper(vars.mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
bindSuper(vars.mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
bindSuper(vars.mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
bindSuper(vars.mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
bindSuper(vars.mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
bindSuper(vars.mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
bindSuper(vars.mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
bindSuper(vars.mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
bindSuper(vars.mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
bindSuper(vars.mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

bindSuper(vars.mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
bindSuper(vars.mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
bindSuper(vars.mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
bindSuper(vars.mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
bindSuper(vars.mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
bindSuper(vars.mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
bindSuper(vars.mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
bindSuper(vars.mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
bindSuper(vars.mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
bindSuper(vars.mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- ── Mouse ─────────────────────────────────────────
bindSuper(vars.mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bindSuper(vars.mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

