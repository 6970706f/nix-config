pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for the shell's look. Colors come from matugen, generated from the
// wallpaper awww is showing; black and white apply when that is turned off or until the first
// palette exists. Change colors here, not in modules.
Singleton {
    id: theme

    readonly property string colorsPath: String(Quickshell.env("HOME") || "")
        + "/.local/state/quickshell/wallpaper-colors.json"

    property bool wallpaperColors: true
    property bool settingsLoaded: false
    property var wallpaperPalette: ({})
    property string wallpaper: ""
    readonly property bool switchingColors: gtkSwitch.running
    readonly property string gtkColorsCommand: String(Quickshell.env("HOME") || "")
        + "/.config/matugen/gtk-wallpaper-colors"

    readonly property var palette: settingsLoaded && wallpaperColors ? wallpaperPalette : ({})

    // Surfaces, from the panel floor up to the hover state.
    readonly property color base: palette.background || "#000000"
    readonly property color surface: palette.surface_container || "#141414"
    readonly property color raised: palette.surface_container_high || "#262626"
    readonly property color hover: palette.surface_container_highest || "#3a3a3a"
    readonly property color stroke: tint(text, 0.16)

    readonly property color text: palette.on_surface || "#ffffff"
    readonly property color subtle: palette.on_surface_variant || "#b3b3b3"
    readonly property color muted: palette.outline || "#7a7a7a"
    readonly property color onAccent: palette.on_primary || "#000000"

    readonly property color iris: palette.primary || "#ffffff"
    readonly property color rose: palette.secondary || "#ffffff"
    readonly property color foam: palette.tertiary || "#ffffff"

    // These keep their meaning on any wallpaper: errors, warnings and success.
    readonly property color love: palette.error || "#ffffff"
    readonly property color gold: palette.gold || "#ffffff"
    readonly property color mint: palette.mint || "#ffffff"

    readonly property Gradient dusk: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: theme.foam }
        GradientStop { position: 0.5; color: theme.rose }
        GradientStop { position: 1.0; color: theme.iris }
    }

    readonly property string fontFamily: "Inter"
    readonly property string displayFont: "Inter Display"
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"

    // Bar geometry. Tabs hang from the screen edge; exclusiveZone leaves the rest to gaps_out.
    readonly property int tabHeight: 38
    readonly property int barHeight: 44
    readonly property int barExclusiveZone: 38

    // Popups reserve room around the card for its shadow.
    readonly property int popupPadX: 18
    readonly property int popupPadTop: 6
    readonly property int popupPadBottom: 28
    readonly property int popupPadY: popupPadTop + popupPadBottom

    readonly property int radiusCard: 24
    readonly property int radiusTile: 16

    readonly property int fast: 130
    readonly property int normal: 220

    readonly property var icons: ({
        nix: "",
        search: cp(0xF0349),
        cpu: cp(0xF0EE0),
        memory: cp(0xF035B),
        disk: cp(0xF02CA),
        volumeHigh: cp(0xF057E),
        volumeMid: cp(0xF0580),
        volumeOff: cp(0xF0581),
        mic: cp(0xF036C),
        micOff: cp(0xF036D),
        record: cp(0xF044A),
        bluetooth: cp(0xF00AF),
        bluetoothOff: cp(0xF00B2),
        wifi1: cp(0xF091F),
        wifi2: cp(0xF0922),
        wifi3: cp(0xF0925),
        wifi4: cp(0xF0928),
        wifiOff: cp(0xF092D),
        ethernet: cp(0xF0200),
        lock: cp(0xF033E),
        power: cp(0xF0425),
        check: cp(0xF012C),
        refresh: cp(0xF0450),
        trash: cp(0xF0A7A),
        swap: cp(0xF04E1),
        chevronLeft: cp(0xF0141),
        chevronRight: cp(0xF0142),
        star: cp(0xF04CE),
        starOutline: cp(0xF04D2),
        play: cp(0xF040A),
        pause: cp(0xF03E4),
        previous: cp(0xF04AE),
        next: cp(0xF04AD),
        music: cp(0xF075A),
        musicNote: cp(0xF0386),
        image: cp(0xF02E9),
        calendar: cp(0xF00ED),
        battery: cp(0xF0079),
        batteryCharging: cp(0xF0084),
        sun: cp(0xF0599),
        partlyCloudy: cp(0xF0595),
        cloudy: cp(0xF0590),
        fog: cp(0xF0591),
        rain: cp(0xF0597),
        snow: cp(0xF0598),
        storm: cp(0xF0593),
        apps: cp(0xF003B),
        bell: cp(0xF009A),
        bellOutline: cp(0xF009C),
        bellOff: cp(0xF009B),
        close: cp(0xF0156),
        chevronDown: cp(0xF0140),
        chevronUp: cp(0xF0143)
    })

    function cp(code) {
        return String.fromCodePoint(code);
    }

    function tint(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    // Meters stay in their own hue until the value becomes worth noticing.
    function levelColor(percent, normalColor) {
        if (percent >= 90)
            return love;
        return percent >= 70 ? gold : normalColor;
    }

    function syncWallpaper() {
        if (wallpaperColors && !wallpaperQuery.running && !colorGenerator.running)
            wallpaperQuery.running = true;
    }

    function loadPalette() {
        try {
            wallpaperPalette = JSON.parse(colorsFile.text());
        } catch (error) {
            console.warn("Theme: could not read", colorsPath, error);
        }
    }

    function saveSettings() {
        settingsFile.setText(JSON.stringify({ wallpaperColors: wallpaperColors }));
    }

    // Shell and GTK switch together: the shell only follows once GTK has, so a failure
    // leaves both off.
    function setWallpaperColors(enabled) {
        if (gtkSwitch.running)
            return;
        gtkSwitch.enabling = enabled;
        gtkSwitch.running = true;
    }

    function restoreSettings() {
        try {
            const raw = settingsFile.text();
            const settings = raw && raw.trim().length > 0 ? JSON.parse(raw) : null;
            if (settings)
                wallpaperColors = settings.wallpaperColors !== false;
        } catch (error) {
            console.warn("Theme: could not read settings:", error);
        }
        settingsLoaded = true;
        gtkStatus.running = true;
    }

    FileView {
        id: settingsFile
        path: Quickshell.statePath("theme.json")
        printErrors: false
        watchChanges: false
        onLoaded: theme.restoreSettings()
        onLoadFailed: theme.restoreSettings()
        onSaveFailed: function(error) {
            console.warn("Theme: settings write failed:", error);
        }
    }

    FileView {
        id: colorsFile
        path: theme.colorsPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme.loadPalette()
    }

    // awww has no change events, and wallpapers can also be set from outside the shell.
    Timer {
        interval: 3000
        running: theme.settingsLoaded && theme.wallpaperColors
        repeat: true
        triggeredOnStart: true
        onTriggered: theme.syncWallpaper()
    }

    Process {
        id: gtkSwitch
        property bool enabling: false
        command: ["bash", theme.gtkColorsCommand, enabling ? "on" : "off"]

        stderr: StdioCollector {
            id: gtkSwitchErrors
        }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                console.warn("Theme: GTK colors failed:", gtkSwitchErrors.text.trim());
                if (enabling)
                    Quickshell.execDetached(["bash", theme.gtkColorsCommand, "off"]);
            }
            theme.wallpaperColors = enabling && exitCode === 0;
            theme.saveSettings();
        }
    }

    // GTK keeps its state on disk, so it can disagree with the saved setting at startup.
    Process {
        id: gtkStatus
        command: ["bash", theme.gtkColorsCommand, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.startsWith("on") !== theme.wallpaperColors)
                    theme.setWallpaperColors(theme.wallpaperColors);
            }
        }
    }

    Process {
        id: wallpaperQuery
        command: ["awww", "query"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = this.text.match(/currently displaying: image: (.+)$/m);
                if (!match || !theme.wallpaperColors || match[1] === theme.wallpaper)
                    return;
                theme.wallpaper = match[1];
                colorGenerator.running = true;
                Quickshell.execDetached(["bash", theme.gtkColorsCommand, "sync", match[1]]);
            }
        }
    }

    // Grayscale images have no source color and would fall back to an unrelated hue, so
    // they get the monochrome scheme instead.
    Process {
        id: colorGenerator
        command: [
            "bash", "-c",
            'config="$1/../matugen/config.toml"\n' +
            '[ -f "$config" ] || config="$HOME/.config/matugen/config.toml"\n' +
            'neutral="#808080"\n' +
            'sources=$(matugen image "$2" -c "$config" --show-source-colors --fallback-color "$neutral") || exit 1\n' +
            'scheme=scheme-tonal-spot\n' +
            '[ "$sources" = "$neutral" ] && scheme=scheme-monochrome\n' +
            'exec matugen image "$2" -c "$config" -q --mode dark --type "$scheme" ' +
            '--source-color-index 0 --fallback-color "$neutral"',
            "ThemeColors",
            Quickshell.shellDir,
            theme.wallpaper
        ]

        stderr: StdioCollector {
            id: generatorErrors
        }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0)
                console.warn("Theme: matugen failed:", generatorErrors.text.trim());
            colorsFile.reload();
        }
    }
}
