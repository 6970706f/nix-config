pragma Singleton

import Quickshell
import QtQuick

// Single source of truth for the shell's look: strictly black and white, with grays for
// depth. Every accent is white, so change colors here, not in modules.
Singleton {
    id: theme

    // Surfaces, from the panel floor up to the hover state.
    readonly property color base: "#000000"
    readonly property color surface: "#141414"
    readonly property color raised: "#262626"
    readonly property color hover: "#3a3a3a"
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.16)

    readonly property color text: "#ffffff"
    readonly property color subtle: "#b3b3b3"
    readonly property color muted: "#7a7a7a"
    readonly property color onAccent: "#000000"

    readonly property color iris: "#ffffff"
    readonly property color rose: "#ffffff"
    readonly property color love: "#ffffff"
    readonly property color gold: "#ffffff"
    readonly property color foam: "#ffffff"
    readonly property color mint: "#ffffff"

    readonly property Gradient dusk: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: theme.gold }
        GradientStop { position: 0.5; color: theme.love }
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
}
