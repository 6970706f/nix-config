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
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Barra: escala única para altura, margens e separação entre grupos.
    readonly property int barHeight: 28
    readonly property int barEdgeMargin: 24
    readonly property int barModuleSpacing: 16
    readonly property int barGroupSpacing: 12

    property string networkIcon: "󰖪"
    property bool recording: false
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

    // O áudio e o microfone usam os nós padrão atuais do PipeWire.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // Mantém o estado de rede compatível com o que a Waybar exibia.
    // Usa nmcli para manter o estado e o ícone da rede compatíveis com a barra anterior.
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
                const address = fields[1] || "IP indisponível";
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

    // Equivalente ao custom/recorder: observa o mesmo arquivo de estado.
    Process {
        id: recordingProcess
        command: ["sh", "-c", 'if [ -n "$XDG_RUNTIME_DIR" ] && [ -f "$XDG_RUNTIME_DIR/recording.state" ]; then printf recording; fi']
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.recording = this.text.trim() === "recording"
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

            // Região esquerda: lançador do NixOS.
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
                        font.bold: true
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

            // Região central: workspaces existentes, com algarismos romanos.
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
                            font.bold: true
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

            // Região direita dividida por função: estado, recursos, conectividade e controles.
            Row {
                id: rightModules
                anchors.right: parent.right
                anchors.rightMargin: root.barEdgeMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.barGroupSpacing

                Row {
                    id: statusModules
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 0
                        text: "󰝥"
                        visible: root.recording
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Item {
                        width: microphoneLabel.implicitWidth
                        height: 22

                        visible: Pipewire.defaultAudioSource !== null
                            && Pipewire.defaultAudioSource.audio !== null
                            && Pipewire.defaultAudioSource.audio.muted

                        Text {
                            id: microphoneLabel
                            anchors.centerIn: parent
                            text: "󰍭"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }

                Row {
                    id: resourceModules
                    spacing: 10

                    Item {
                        id: cpuModule
                        width: cpuLabel.implicitWidth + 6
                        height: 22

                        Text {
                            id: cpuLabel
                            anchors.centerIn: parent
                            text: "󰻠 " + systemMonitorPanel.cpuUsage + "%"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
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
                        width: memoryLabel.implicitWidth + 6
                        height: 22

                        Text {
                            id: memoryLabel
                            anchors.centerIn: parent
                            text: "󰍛 " + systemMonitorPanel.memoryUsage + "%"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
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
                            font.bold: true
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
                            font.bold: true
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
                        width: audioLabel.implicitWidth
                        height: 22

                        Text {
                            id: audioLabel
                            anchors.centerIn: parent
                            text: {
                                const sink = Pipewire.defaultAudioSink;
                                if (!sink || !sink.audio)
                                    return "  --%";
                                if (sink.audio.muted)
                                    return " ";
                                return "  " + Math.round(sink.audio.volume * 100) + "%";
                            }
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
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
                        width: clockLabel.implicitWidth
                        height: 22

                        Text {
                            id: clockLabel
                            anchors.centerIn: parent
                            text: "󰥔 " + Qt.formatDateTime(systemClock.date, "HH:mm")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
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
                            text: "󰐥"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
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
            }

            SoundPanel {
                id: soundPanel
                anchorWindow: barWindow
                anchorItem: audioModule
            }

            CalendarPanel {
                id: calendarPanel
                anchorWindow: barWindow
                anchorItem: clockModule
            }

            PowerPanel {
                id: powerPanel
                anchorWindow: barWindow
                anchorItem: powerModule
            }

            BluetoothPanel {
                id: bluetoothPanel
                anchorWindow: barWindow
                anchorItem: bluetoothModule
            }

            SystemMonitorPanel {
                id: systemMonitorPanel
                anchorWindow: barWindow
                anchorItem: cpuModule
            }

            AppLauncher {
                id: appLauncher
                anchorWindow: barWindow

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
