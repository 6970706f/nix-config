import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls

Scope {
    id: root

    property string networkIcon: "󰖪"
    property bool batteryAvailable: false
    property int batteryPercent: 0
    property string batteryStatus: "Unknown"
    property string batteryModel: "Battery"
    property string batteryIcon: "󰂑"
    property bool recording: false
    readonly property bool microphoneMuted: Pipewire.defaultAudioSource !== null
        && Pipewire.defaultAudioSource.audio !== null
        && Pipewire.defaultAudioSource.audio.muted
    property var appLauncherInstances: []

    function registerAppLauncher(instance) {
        const instances = root.appLauncherInstances.slice();

        if (instances.indexOf(instance) === -1) {
            instances.push(instance);
            root.appLauncherInstances = instances;
        }
    }

    function unregisterAppLauncher(instance) {
        root.appLauncherInstances = root.appLauncherInstances.filter(
            function(candidate) {
                return candidate !== instance;
            }
        );
    }

    function toggleAppLauncher() {
        const launcher = root.appLauncherInstances.length > 0
            ? root.appLauncherInstances[0]
            : null;

        if (launcher) {
            launcher.togglePanel();
        } else {
            console.warn("AppLauncher IPC: no launcher instance is registered.");
        }
    }

    IpcHandler {
        target: "appLauncher"

        function toggle(): void {
            root.toggleAppLauncher();
        }
    }

    // Audio and microphone use the current default PipeWire nodes.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // Keeps the network state compatible with what Waybar displayed.
    // Uses nmcli to keep the network state and icon compatible with the previous bar.
    Process {
        id: networkProcess
        command: ["sh", "-c", `
            export LC_ALL=C
            wifi_device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')
            eth_device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "ethernet" && $3 ~ /^connected/ { print $1; exit }')

            if [ -n "$eth_device" ]; then
                ip=$(nmcli -g IP4.ADDRESS device show "$eth_device" | head -n 1 | cut -d/ -f1)
                printf 'ethernet|%s|0\\n' "$ip"
            elif [ -n "$wifi_device" ]; then
                ip=$(nmcli -g IP4.ADDRESS device show "$wifi_device" | head -n 1 | cut -d/ -f1)
                signal=$(nmcli -t -f IN-USE,SIGNAL device wifi | awk -F: '$1 == "*" { print $2; exit }')
                printf 'wifi|%s|%s\\n' "$ip" "$signal"
            else
                printf 'disconnected||0\\n'
            fi
        `]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const fields = this.text.trim().split("|");
                const state = fields[0] || "disconnected";
                const address = fields[1] || "IP unavailable";
                const signal = fields[2] || "0";

                if (state === "wifi")
                    root.networkIcon = "󰖩";
                else if (state === "ethernet")
                    root.networkIcon = "󰈀";
                else
                    root.networkIcon = "󰖪";
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!networkProcess.running)
                networkProcess.running = true;
        }
    }

    // Equivalent to custom/recorder: watches the same state file.
    Process {
        id: recordingProcess
        command: ["sh", "-c", 'if [ -n "$XDG_RUNTIME_DIR" ] && [ -f "$XDG_RUNTIME_DIR/recording.state" ]; then printf recording; fi']
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.recording = this.text.trim() === "recording"
        }
    }

    // A battery module is present only when Linux exposes a battery power supply.
    Process {
        id: batteryProcess
        command: ["sh", "-c", `
            for battery in /sys/class/power_supply/*; do
                [ -r "$battery/type" ] || continue
                [ "$(cat "$battery/type")" = "Battery" ] || continue
                capacity=$(cat "$battery/capacity" 2>/dev/null || printf 0)
                status=$(cat "$battery/status" 2>/dev/null || printf Unknown)
                model=$(cat "$battery/model_name" 2>/dev/null || basename "$battery")
                printf '%s|%s|%s\\n' "$capacity" "$status" "$model"
                exit
            done
        `]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const fields = this.text.trim().split("|");
                root.batteryAvailable = fields.length >= 3 && fields[0].length > 0;
                if (root.batteryAvailable) {
                    root.batteryPercent = Math.max(0, Math.min(100, parseInt(fields[0]) || 0));
                    root.batteryStatus = fields[1] || "Unknown";
                    root.batteryModel = fields[2] || "Battery";
                    root.batteryIcon = root.batteryStatus === "Charging" ? "󰂄"
                        : (root.batteryPercent >= 90 ? "󰁹"
                        : (root.batteryPercent >= 70 ? "󰂀"
                        : (root.batteryPercent >= 50 ? "󰁾"
                        : (root.batteryPercent >= 30 ? "󰁼"
                        : (root.batteryPercent >= 10 ? "󰁺" : "󰂎")))));
                }
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!batteryProcess.running)
                batteryProcess.running = true;
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (!recordingProcess.running)
                recordingProcess.running = true;
        }
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow

            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: Theme.barHeight
            exclusiveZone: Theme.barExclusiveZone
            color: "transparent"

            // Left tab: NixOS launcher and workspaces.
            BarTab {
                id: leftTab
                anchors.left: parent.left
                anchors.top: parent.top
                sidePadding: 6
                spacing: 10

                Item {
                    id: launcherModule
                    width: 30
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        gradient: Theme.dusk
                        scale: launcherMouse.pressed ? 0.92 : (launcherMouse.containsMouse ? 1.06 : 1)

                        Behavior on scale {
                            NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack }
                        }
                    }

                    // The snowflake has six-fold symmetry, so a 60 degree turn loops cleanly.
                    Icon {
                        anchors.centerIn: parent
                        text: Theme.icons.nix
                        color: Theme.onAccent
                        font.pixelSize: 17
                        rotation: launcherMouse.containsMouse ? 60 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        id: launcherMouse
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (networkPanel.visible)
                                networkPanel.closePanel();
                            if (soundPanel.visible)
                                soundPanel.closePanel();
                            if (calendarPanel.visible)
                                calendarPanel.closePanel();
                            if (bluetoothPanel.visible)
                                bluetoothPanel.closePanel();
                            if (systemMonitorPanel.visible)
                                systemMonitorPanel.closePanel();
                            if (powerPanel.visible)
                                powerPanel.closePanel();
                            appLauncher.togglePanel();
                        }
                    }
                }

                // Occupied workspaces; the active one stretches into a gradient pill.
                Row {
                    id: workspaceModules
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: Hyprland.workspaces

                        delegate: Item {
                            id: workspaceItem

                            required property var modelData
                            readonly property var targetMonitor: {
                                settled;
                                return Hyprland.monitorFor(barWindow.screen);
                            }
                            readonly property bool isActive: modelData.active
                            readonly property bool isUrgent: modelData.urgent && !modelData.active

                            // monitorFor() is not reactive and returns null for the first delegate on a
                            // fresh start, which hid that workspace; look it up again once things settle.
                            property bool settled: false

                            Timer {
                                running: true
                                interval: 500
                                onTriggered: workspaceItem.settled = true
                            }

                            visible: modelData.monitor !== null
                                && modelData.monitor !== undefined
                                && targetMonitor !== null
                                && modelData.monitor.name === targetMonitor.name
                                && (modelData.active || modelData.urgent || modelData.toplevels.values.length > 0)
                            width: visible ? (isActive ? 42 : 26) : 0
                            height: 26

                            Behavior on width {
                                NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: workspaceItem.isUrgent
                                    ? Theme.love
                                    : (workspaceMouse.containsMouse ? Theme.hover : Theme.surface)

                                Behavior on color {
                                    ColorAnimation { duration: Theme.fast }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                gradient: Theme.dusk
                                opacity: workspaceItem.isActive ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.normal }
                                }
                            }

                            UiText {
                                anchors.centerIn: parent
                                text: workspaceItem.modelData.name
                                color: workspaceItem.isActive || workspaceItem.isUrgent
                                    ? Theme.onAccent
                                    : Theme.subtle
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                id: workspaceMouse
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: workspaceItem.modelData.activate()
                            }
                        }
                    }
                }
            }

            // Center tab: the clock stays on the screen's axis; music docks beside it.
            BarTab {
                id: clockTab
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                sidePadding: 8

                Item {
                    id: clockModule
                    width: clockContent.implicitWidth + 20
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: clockMouse.containsMouse ? Theme.raised : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.fast }
                        }
                    }

                    Row {
                        id: clockContent
                        anchors.centerIn: parent
                        spacing: 9

                        UiText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDateTime(systemClock.date, "HH:mm")
                            font.family: Theme.displayFont
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.love
                        }

                        UiText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: systemClock.date.toLocaleDateString(Qt.locale("en_US"), "ddd, d MMM")
                            color: Theme.subtle
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: clockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (networkPanel.visible)
                                networkPanel.closePanel();
                            if (soundPanel.visible)
                                soundPanel.closePanel();
                            if (bluetoothPanel.visible)
                                bluetoothPanel.closePanel();
                            if (systemMonitorPanel.visible)
                                systemMonitorPanel.closePanel();
                            if (appLauncher.visible)
                                appLauncher.closePanel();
                            if (powerPanel.visible)
                                powerPanel.closePanel();
                            calendarPanel.togglePanel();
                        }
                    }
                }
            }

            // Spotifast player component between the clock and right-side modules.
            MusicPlayer {
                id: musicPlayerModule
                anchors.left: clockTab.right
                anchors.leftMargin: 4
                anchors.right: statusTab.left
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchorWindow: barWindow

                onCloseOtherPanelsRequested: {
                    if (networkPanel.visible)
                        networkPanel.closePanel();
                    if (soundPanel.visible)
                        soundPanel.closePanel();
                    if (calendarPanel.visible)
                        calendarPanel.closePanel();
                    if (bluetoothPanel.visible)
                        bluetoothPanel.closePanel();
                    if (systemMonitorPanel.visible)
                        systemMonitorPanel.closePanel();
                    if (powerPanel.visible)
                        powerPanel.closePanel();
                    if (appLauncher.visible)
                        appLauncher.closePanel();
                }
            }

            // Right tab: alerts, resources, connectivity and audio.
            BarTab {
                id: statusTab
                anchors.right: powerTab.left
                anchors.rightMargin: 2
                anchors.top: parent.top
                sidePadding: 6
                spacing: 6

                // Only takes up room while there is something to warn about.
                Row {
                    id: statusModules
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.recording || root.microphoneMuted
                    spacing: 6

                    Item {
                        id: recordingIndicatorModule
                        visible: root.recording
                        width: 22
                        height: 28

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: Theme.love

                            SequentialAnimation on opacity {
                                running: root.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    Rectangle {
                        id: microphoneLabel
                        visible: root.microphoneMuted
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.tint(Theme.love, 0.18)

                        Icon {
                            anchors.centerIn: parent
                            text: Theme.icons.micOff
                            color: Theme.love
                            font.pixelSize: 15
                        }
                    }
                }

                BarGauge {
                    id: cpuModule
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Theme.icons.cpu
                    percent: systemMonitorPanel.cpuUsage
                    accent: Theme.iris
                    onClicked: {
                        if (networkPanel.visible)
                            networkPanel.closePanel();
                        if (soundPanel.visible)
                            soundPanel.closePanel();
                        if (calendarPanel.visible)
                            calendarPanel.closePanel();
                        if (bluetoothPanel.visible)
                            bluetoothPanel.closePanel();
                        if (appLauncher.visible)
                            appLauncher.closePanel();
                        if (powerPanel.visible)
                            powerPanel.closePanel();
                        systemMonitorPanel.anchorItem = cpuModule;
                        systemMonitorPanel.togglePanel("cpu");
                    }
                }

                BarGauge {
                    id: memoryModule
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Theme.icons.memory
                    percent: systemMonitorPanel.memoryUsage
                    accent: Theme.foam
                    onClicked: {
                        if (networkPanel.visible)
                            networkPanel.closePanel();
                        if (soundPanel.visible)
                            soundPanel.closePanel();
                        if (calendarPanel.visible)
                            calendarPanel.closePanel();
                        if (bluetoothPanel.visible)
                            bluetoothPanel.closePanel();
                        if (appLauncher.visible)
                            appLauncher.closePanel();
                        if (powerPanel.visible)
                            powerPanel.closePanel();
                        systemMonitorPanel.anchorItem = memoryModule;
                        systemMonitorPanel.togglePanel("memory");
                    }
                }

                BarGauge {
                    id: batteryModule
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.batteryAvailable
                    glyph: root.batteryIcon
                    percent: root.batteryPercent
                    accent: root.batteryPercent <= 15 ? Theme.love : Theme.mint
                    onClicked: {
                        if (networkPanel.visible) networkPanel.closePanel();
                        if (soundPanel.visible) soundPanel.closePanel();
                        if (calendarPanel.visible) calendarPanel.closePanel();
                        if (bluetoothPanel.visible) bluetoothPanel.closePanel();
                        if (systemMonitorPanel.visible) systemMonitorPanel.closePanel();
                        if (appLauncher.visible) appLauncher.closePanel();
                        if (powerPanel.visible) powerPanel.closePanel();
                        batteryPanel.togglePanel();
                    }
                }

                BarIconButton {
                    id: bluetoothModule
                    anchors.verticalCenter: parent.verticalCenter
                    active: !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                    glyph: active ? Theme.icons.bluetooth : Theme.icons.bluetoothOff
                    accent: Theme.iris
                    onClicked: {
                        if (networkPanel.visible)
                            networkPanel.closePanel();
                        if (soundPanel.visible)
                            soundPanel.closePanel();
                        if (calendarPanel.visible)
                            calendarPanel.closePanel();
                        if (systemMonitorPanel.visible)
                            systemMonitorPanel.closePanel();
                        if (appLauncher.visible)
                            appLauncher.closePanel();
                        if (powerPanel.visible)
                            powerPanel.closePanel();
                        bluetoothPanel.togglePanel();
                    }
                }

                BarIconButton {
                    id: networkModule
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.networkIcon !== "󰖪"
                    glyph: root.networkIcon
                    accent: Theme.foam
                    onClicked: {
                        if (soundPanel.visible)
                            soundPanel.closePanel();
                        if (calendarPanel.visible)
                            calendarPanel.closePanel();
                        if (bluetoothPanel.visible)
                            bluetoothPanel.closePanel();
                        if (systemMonitorPanel.visible)
                            systemMonitorPanel.closePanel();
                        if (appLauncher.visible)
                            appLauncher.closePanel();
                        if (powerPanel.visible)
                            powerPanel.closePanel();
                        networkPanel.togglePanel();
                    }
                }

                Item {
                    id: audioModule
                    anchors.verticalCenter: parent.verticalCenter
                    width: 108
                    height: 28

                    readonly property bool hasSink: !!Pipewire.defaultAudioSink && !!Pipewire.defaultAudioSink.audio
                    readonly property bool isMuted: hasSink && Pipewire.defaultAudioSink.audio.muted
                    readonly property real level: hasSink ? Pipewire.defaultAudioSink.audio.volume : 0

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: audioMouse.containsMouse ? Theme.raised : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.fast }
                        }
                    }

                    Icon {
                        id: audioIcon
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        text: audioModule.isMuted || !audioModule.hasSink
                            ? Theme.icons.volumeOff
                            : (audioModule.level < 0.5 ? Theme.icons.volumeMid : Theme.icons.volumeHigh)
                        color: audioModule.isMuted ? Theme.muted : Theme.rose
                        font.pixelSize: 15
                    }

                    MeterBar {
                        anchors.left: audioIcon.right
                        anchors.leftMargin: 6
                        anchors.right: audioValue.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        value: audioModule.isMuted ? 0 : audioModule.level
                        accent: Theme.rose
                    }

                    UiText {
                        id: audioValue
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        horizontalAlignment: Text.AlignRight
                        text: {
                            const sink = Pipewire.defaultAudioSink;
                            if (!sink || !sink.audio)
                                return "--";
                            if (sink.audio.muted)
                                return "off";
                            return Math.round(sink.audio.volume * 100) + "%";
                        }
                        color: audioModule.isMuted ? Theme.muted : Theme.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: audioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                        onClicked: {
                            const sink = Pipewire.defaultAudioSink;
                            if (mouse.button === Qt.LeftButton) {
                                if (networkPanel.visible)
                                    networkPanel.closePanel();
                                if (calendarPanel.visible)
                                    calendarPanel.closePanel();
                                if (bluetoothPanel.visible)
                                    bluetoothPanel.closePanel();
                                if (systemMonitorPanel.visible)
                                    systemMonitorPanel.closePanel();
                                if (appLauncher.visible)
                                    appLauncher.closePanel();
                                if (powerPanel.visible)
                                    powerPanel.closePanel();
                                soundPanel.togglePanel();
                            } else if ((mouse.button === Qt.RightButton
                                        || mouse.button === Qt.MiddleButton) && sink && sink.audio) {
                                sink.audio.muted = !sink.audio.muted;
                            }
                        }

                        onWheel: {
                            const sink = Pipewire.defaultAudioSink;
                            if (!sink || !sink.audio)
                                return;

                            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                            sink.audio.volume = Math.max(0, sink.audio.volume + step);
                            wheel.accepted = true;
                        }
                    }
                }
            }

            BarTab {
                id: powerTab
                anchors.right: parent.right
                anchors.top: parent.top
                sidePadding: 4

                BarIconButton {
                    id: powerModule
                    glyph: Theme.icons.power
                    accent: Theme.love
                    onClicked: {
                        if (networkPanel.visible)
                            networkPanel.closePanel();
                        if (soundPanel.visible)
                            soundPanel.closePanel();
                        if (calendarPanel.visible)
                            calendarPanel.closePanel();
                        if (bluetoothPanel.visible)
                            bluetoothPanel.closePanel();
                        if (systemMonitorPanel.visible)
                            systemMonitorPanel.closePanel();
                        if (appLauncher.visible)
                            appLauncher.closePanel();
                        powerPanel.togglePanel();
                    }
                }
            }

            NetworkPanel {
                id: networkPanel
                anchorWindow: barWindow
                anchorItem: networkModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            SoundPanel {
                id: soundPanel
                anchorWindow: barWindow
                anchorItem: audioModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            CalendarPanel {
                id: calendarPanel
                anchorWindow: barWindow
                anchorItem: clockModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            PowerPanel {
                id: powerPanel
                anchorWindow: barWindow
                anchorItem: powerModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            BatteryPanel {
                id: batteryPanel
                anchorWindow: barWindow
                anchorItem: batteryModule
                batteryPercent: root.batteryPercent
                batteryStatus: root.batteryStatus
                batteryModel: root.batteryModel

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            BluetoothPanel {
                id: bluetoothPanel
                anchorWindow: barWindow
                anchorItem: bluetoothModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            SystemMonitorPanel {
                id: systemMonitorPanel
                anchorWindow: barWindow
                anchorItem: cpuModule

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }
            }

            AppLauncher {
                id: appLauncher
                anchorWindow: barWindow

                onVisibleChanged: {
                    if (visible)
                        musicPlayerModule.closePanel();
                }

                Component.onCompleted: {
                    root.registerAppLauncher(appLauncher);
                }

                Component.onDestruction: {
                    root.unregisterAppLauncher(appLauncher);
                }
            }
        }
    }
}
