import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls

Scope {
    id: root

    readonly property color backgroundColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"

    // Bar: a single scale for height, margins, and spacing between groups.
    readonly property int barHeight: 28
    readonly property int barEdgeMargin: 24
    readonly property int barModuleSpacing: 16
    readonly property int barGroupSpacing: 12

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

    readonly property var romanNumerals: ({
        "1": "I",
        "2": "II",
        "3": "III",
        "4": "IV",
        "5": "V",
        "6": "VI",
        "7": "VII",
        "8": "VIII",
        "9": "IX",
        "10": "X"
    })

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

            implicitHeight: root.barHeight
            exclusiveZone: implicitHeight
            color: root.backgroundColor

            margins {
                top: 0
                bottom: 1
                left: 0
                right: 0
            }

            // Left section: NixOS launcher.
            Row {
                id: leftModules
                anchors.left: parent.left
                anchors.leftMargin: root.barEdgeMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.barModuleSpacing

                Item {
                    width: nixIcon.implicitWidth + 5
                    height: 22

                    Text {
                        id: nixIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.bold: false
                    }

                    MouseArea {
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
            }

            // Center section: existing workspaces, using Roman numerals.
            Row {
                id: workspaceModules
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: Hyprland.workspaces

                    delegate: Item {
                        id: workspaceItem

                        required property var modelData
                        readonly property var targetMonitor: Hyprland.monitorFor(barWindow.screen)

                        visible: modelData.monitor !== null
                            && modelData.monitor !== undefined
                            && targetMonitor !== null
                            && modelData.monitor.name === targetMonitor.name
                            && (modelData.active || modelData.urgent || modelData.toplevels.values.length > 0)
                        width: visible ? workspaceLabel.implicitWidth + 12 : 0
                        height: 24

                        Text {
                            id: workspaceLabel
                            anchors.centerIn: parent
                            text: root.romanNumerals[String(workspaceItem.modelData.id)]
                                || workspaceItem.modelData.name
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            font.bold: false
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: workspaceItem.modelData.active || workspaceItem.modelData.urgent
                                ? root.foregroundColor
                                : "transparent"
                        }

                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: workspaceItem.modelData.activate()
                        }
                    }
                }
            }

            // Spotifast player component between workspaces and right-side modules.
            MusicPlayer {
                id: musicPlayerModule
                anchors.left: workspaceModules.right
                anchors.leftMargin: 18
                anchors.right: rightModules.left
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                anchorWindow: barWindow
                foregroundColor: root.foregroundColor
                fontFamily: root.fontFamily

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

            // Right section grouped by function: status, resources, connectivity, and controls.
            Row {
                id: rightModules
                anchors.right: parent.right
                anchors.rightMargin: root.barEdgeMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.barGroupSpacing

                Row {
                    id: statusModules
                    height: 22
                    spacing: 8

                    // The recording indicator has two fixed positions:
                    // CPU-adjacent while the microphone is enabled, and the outer
                    // slot while muted. The microphone uses the CPU-adjacent slot.
                    Item {
                        id: recordingOuterSlot
                        width: 12
                        height: 22

                        Text {
                            anchors.centerIn: parent
                            text: "󰝥"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: false
                            opacity: root.recording && root.microphoneMuted ? 1 : 0
                        }
                    }

                    // Keep this slot reserved so neither icon moves other modules.
                    // Recording and microphone are mutually exclusive in this slot.
                    Item {
                        id: cpuAdjacentStatusSlot
                        width: 16
                        height: 22

                        Text {
                            id: recordingIndicatorModule
                            anchors.centerIn: parent
                            text: "󰝥"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: false
                            opacity: root.recording && !root.microphoneMuted ? 1 : 0
                        }

                        Text {
                            id: microphoneLabel
                            anchors.centerIn: parent
                            text: "󰍭"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                            opacity: root.microphoneMuted ? 1 : 0
                        }
                    }
                }

                Row {
                    id: resourceModules
                    spacing: 8

                    Item {
                        id: cpuModule
                        width: 56
                        height: 22

                        Text {
                            id: cpuLabel
                            anchors.fill: parent
                            anchors.rightMargin: 3
                            text: "󰻠  " + systemMonitorPanel.cpuUsage + "%"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
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
                    }

                    Item {
                        id: memoryModule
                        width: 56
                        height: 22

                        Text {
                            id: memoryLabel
                            anchors.fill: parent
                            anchors.rightMargin: 3
                            text: "󰍛  " + systemMonitorPanel.memoryUsage + "%"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
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
                    }

                    Item {
                        id: batteryModule
                        visible: root.batteryAvailable
                        width: visible ? batteryLabel.implicitWidth + 6 : 0
                        height: 22

                        Text {
                            id: batteryLabel
                            anchors.centerIn: parent
                            text: root.batteryIcon + "  " + root.batteryPercent + "%"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
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
                    }
                }

                Rectangle {
                    width: 1
                    height: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#303030"
                }

                Row {
                    id: connectivityModules
                    spacing: 10

                    Item {
                        id: bluetoothModule
                        width: bluetoothLabel.implicitWidth + 6
                        height: 22

                        Text {
                            id: bluetoothLabel
                            anchors.centerIn: parent
                            text: !Bluetooth.defaultAdapter
                                ? "󰂲"
                                : (Bluetooth.defaultAdapter.enabled ? "󰂯" : "󰂲")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                        }

                        MouseArea {
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
                                if (systemMonitorPanel.visible)
                                    systemMonitorPanel.closePanel();
                                if (appLauncher.visible)
                                    appLauncher.closePanel();
                                if (powerPanel.visible)
                                    powerPanel.closePanel();
                                bluetoothPanel.togglePanel();
                            }
                        }
                    }

                    Item {
                        id: networkModule
                        width: networkLabel.implicitWidth + 6
                        height: 22

                        Text {
                            id: networkLabel
                            anchors.centerIn: parent
                            text: root.networkIcon
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                        }

                        MouseArea {
                            cursorShape: Qt.PointingHandCursor
                            id: networkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: {
                                if (mouse.button === Qt.LeftButton) {
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
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#303030"
                }

                Row {
                    id: controlModules
                    spacing: 12

                    Item {
                        id: audioModule
                        width: 50
                        height: 22

                        Row {
                            id: audioContent
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: audioIcon
                                width: 13
                                text: {
                                    const sink = Pipewire.defaultAudioSink;
                                    if (!sink || !sink.audio)
                                        return "";
                                    return sink.audio.muted ? "" : "";
                                }
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                font.bold: false
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                id: audioValue
                                width: 33
                                text: {
                                    const sink = Pipewire.defaultAudioSink;
                                    if (!sink || !sink.audio)
                                        return "--%";
                                    if (sink.audio.muted)
                                        return "";
                                    return Math.round(sink.audio.volume * 100) + "%";
                                }
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                font.bold: false
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        MouseArea {
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

                    Item {
                        id: clockModule
                        width: 60
                        height: 22

                        Text {
                            id: clockLabel
                            anchors.fill: parent
                            text: "󰥔  " + Qt.formatDateTime(systemClock.date, "HH:mm")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
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

                    Rectangle {
                        width: 1
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#303030"
                    }

                    Item {
                        id: powerModule
                        width: powerLabel.implicitWidth + 6
                        height: 22

                        Text {
                            id: powerLabel
                            anchors.centerIn: parent
                            text: "⏻"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
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
                                if (appLauncher.visible)
                                    appLauncher.closePanel();
                                powerPanel.togglePanel();
                            }
                        }
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
