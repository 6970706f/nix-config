import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color separatorColor: "#303030"
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"

    property string activeTab: "output"
    property string statusMessage: ""

    width: 390
    height: activeTab === "applications" ? 470 : 420
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + 8 : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 8;

        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const minimumX = root.anchorWindow.width >= root.width + 16 ? 8 : 0;
        const maximumX = Math.max(minimumX, root.anchorWindow.width - root.width - minimumX);
        return Math.max(minimumX, Math.min(
            point.x + root.anchorItem.width / 2 - root.width / 2,
            maximumX
        ));
    }

    // Bind every live node so PwNodeAudio volume and mute properties are safe to use.
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(function(node) {
            return node && node.audio !== null && node.audio !== undefined;
        })
    }

    function openPanel() {
        statusMessage = "";
        visible = true;
    }

    function closePanel() {
        visible = false;
    }

    function togglePanel() {
        if (visible)
            closePanel();
        else
            openPanel();
    }

    function audioNodeReady(node) {
        return Pipewire.ready && node !== null && node !== undefined
            && node.ready && node.audio !== null && node.audio !== undefined;
    }

    function nodeLabel(node) {
        if (!node)
            return "Unavailable";
        return String(node.nickname || node.description || node.name || "Unknown device");
    }

    function nodeProperty(node, key) {
        if (!node || !node.ready || !node.properties)
            return "";
        const value = node.properties[key];
        return value === null || value === undefined ? "" : String(value);
    }

    function applicationName(node) {
        return nodeProperty(node, "application.name")
            || nodeProperty(node, "media.name")
            || nodeLabel(node);
    }

    function applicationIconName(node) {
        return nodeProperty(node, "application.icon-name");
    }

    // Only expose application playback streams here, never streams that capture
    // microphone/input audio. Prefer PipeWire's explicit media.class metadata;
    // use graph direction as a fallback for streams without that property.
    function isApplicationOutputStream(node) {
        if (!node || !node.ready || !node.isStream || !node.audio)
            return false;

        const mediaClass = nodeProperty(node, "media.class");
        if (mediaClass === "Stream/Output/Audio")
            return true;
        if (mediaClass === "Stream/Input/Audio")
            return false;

        if (node.isSink)
            return false;

        const groups = Pipewire.linkGroups.values;
        for (let i = 0; i < groups.length; i++) {
            const group = groups[i];
            if (group && group.source && group.source.id === node.id
                && group.target && group.target.isSink)
                return true;
        }
        return false;
    }

    function outputForStream(node) {
        if (!node || !node.ready)
            return "Output: unavailable";

        const groups = Pipewire.linkGroups.values;
        const targets = [];
        for (let i = 0; i < groups.length; i++) {
            const group = groups[i];
            if (!group || !group.source || group.source.id !== node.id
                || !group.target || !group.target.isSink)
                continue;
            const targetName = nodeLabel(group.target);
            if (targets.indexOf(targetName) < 0)
                targets.push(targetName);
        }
        return targets.length > 0 ? "Output: " + targets.join(", ") : "Output: unavailable";
    }

    readonly property var outputDevices: {
        const result = [];
        if (!Pipewire.ready)
            return result;
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (node && node.ready && !node.isStream && node.isSink && node.audio)
                result.push(node);
        }
        result.sort(function(a, b) {
            return root.nodeLabel(a).localeCompare(root.nodeLabel(b));
        });
        return result;
    }

    readonly property var inputDevices: {
        const result = [];
        if (!Pipewire.ready)
            return result;
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (node && node.ready && !node.isStream && !node.isSink && node.audio)
                result.push(node);
        }
        result.sort(function(a, b) {
            return root.nodeLabel(a).localeCompare(root.nodeLabel(b));
        });
        return result;
    }

    readonly property var applicationStreams: {
        const result = [];
        if (!Pipewire.ready)
            return result;
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (root.isApplicationOutputStream(node))
                result.push(node);
        }
        result.sort(function(a, b) {
            return root.applicationName(a).localeCompare(root.applicationName(b));
        });
        return result;
    }

    readonly property string statusLabel: {
        if (!Pipewire.ready)
            return "SYNCING";
        if (activeTab === "output" && outputDevices.length === 0)
            return "NO OUTPUT";
        if (activeTab === "input" && inputDevices.length === 0)
            return "NO INPUT";
        if (activeTab === "applications" && applicationStreams.length === 0)
            return "IDLE";
        return "READY";
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    Rectangle {
        id: outerBorder
        focus: root.visible
        anchors.fill: parent
        color: root.panelColor
        radius: 0
        border.width: 1
        border.color: "#ffffff"

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 0

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰕾  SOUND"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.bold: false
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusLabel
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignRight
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Row {
                id: tabBar
                width: parent.width
                height: 30

                Repeater {
                    model: [
                        { key: "output", label: "OUTPUT" },
                        { key: "input", label: "INPUT" },
                        { key: "applications", label: "APPLICATIONS" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: tabBar.width / 3
                        height: tabBar.height
                        color: root.activeTab === modelData.key
                            ? "#111111"
                            : (tabMouse.containsMouse ? "#080808" : "transparent")

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.activeTab === modelData.key
                                ? root.foregroundColor : root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: root.activeTab === modelData.key ? 2 : 1
                            color: root.activeTab === modelData.key ? "#ffffff" : root.separatorColor
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = modelData.key
                        }
                    }
                }
            }

            Item {
                id: pageArea
                width: parent.width
                height: root.height - 112

                Column {
                    id: outputPage
                    visible: root.activeTab === "output"
                    width: parent.width
                    height: parent.height
                    spacing: 6

                    Column {
                        width: parent.width
                        height: 28
                        spacing: 1

                        Text {
                            text: "DEFAULT OUTPUT"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            width: parent.width
                            text: root.audioNodeReady(Pipewire.defaultAudioSink)
                                ? root.nodeLabel(Pipewire.defaultAudioSink)
                                : (Pipewire.ready ? "No output device selected" : "Waiting for PipeWire...")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: outputVolumeRow
                        width: parent.width
                        height: 52

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: root.audioNodeReady(Pipewire.defaultAudioSink)
                                && Pipewire.defaultAudioSink.audio.muted
                                ? "  MASTER VOLUME"
                                : (root.audioNodeReady(Pipewire.defaultAudioSink)
                                    && Pipewire.defaultAudioSink.audio.volume < 0.5
                                    ? "  MASTER VOLUME" : "  MASTER VOLUME")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        Text {
                            anchors.right: outputMuteButton.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            width: 48
                            horizontalAlignment: Text.AlignRight
                            text: root.audioNodeReady(Pipewire.defaultAudioSink)
                                ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "--%"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }

                        Rectangle {
                            id: outputMuteButton
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: 58
                            height: 20
                            radius: 0
                            color: outputMuteMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                            border.width: 1
                            border.color: "#373737"
                            opacity: root.audioNodeReady(Pipewire.defaultAudioSink) ? 1 : 0.45

                            Text {
                                anchors.centerIn: parent
                                text: root.audioNodeReady(Pipewire.defaultAudioSink)
                                    && Pipewire.defaultAudioSink.audio.muted ? "UNMUTE" : "MUTE"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: outputMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.audioNodeReady(Pipewire.defaultAudioSink)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const node = Pipewire.defaultAudioSink;
                                    if (root.audioNodeReady(node))
                                        node.audio.muted = !node.audio.muted;
                                }
                            }
                        }

                        Slider {
                            id: outputVolumeSlider
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 27
                            height: 22
                            from: 0
                            to: 1.5
                            stepSize: 0.01
                            enabled: root.audioNodeReady(Pipewire.defaultAudioSink)
                            value: enabled ? Pipewire.defaultAudioSink.audio.volume : 0
                            onMoved: {
                                const node = Pipewire.defaultAudioSink;
                                if (root.audioNodeReady(node))
                                    node.audio.volume = value;
                            }
                            background: Rectangle {
                                x: outputVolumeSlider.leftPadding
                                y: outputVolumeSlider.topPadding + outputVolumeSlider.availableHeight / 2 - height / 2
                                width: outputVolumeSlider.availableWidth
                                height: 3
                                color: "#303030"
                                Rectangle {
                                    width: outputVolumeSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#ffffff"
                                }
                            }
                            handle: Rectangle {
                                x: outputVolumeSlider.leftPadding
                                    + outputVolumeSlider.visualPosition * (outputVolumeSlider.availableWidth - width)
                                y: outputVolumeSlider.topPadding + outputVolumeSlider.availableHeight / 2 - height / 2
                                width: 6
                                height: 12
                                radius: 0
                                color: "#ffffff"
                                border.width: 1
                                border.color: "#ffffff"
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.separatorColor
                    }

                    Item {
                        width: parent.width
                        height: 17
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "AVAILABLE OUTPUTS"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(0, parent.height - 122)

                        ListView {
                            id: outputDeviceList
                            anchors.fill: parent
                            visible: root.outputDevices.length > 0
                            clip: true
                            spacing: 4
                            model: root.outputDevices

                            delegate: Item {
                                required property var modelData
                                width: outputDeviceList.width
                                height: 36

                                readonly property bool isDefault: Pipewire.defaultAudioSink !== null
                                    && Pipewire.defaultAudioSink !== undefined
                                    && Pipewire.defaultAudioSink.id === modelData.id

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 0
                                    color: parent.isDefault ? "#111111" : "#0c0c0c"
                                    border.width: 1
                                    border.color: parent.isDefault ? "#454545" : "#303030"
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 9
                                    anchors.right: deviceDefaultLabel.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.nodeLabel(modelData)
                                    color: root.foregroundColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: deviceDefaultLabel
                                    anchors.right: parent.right
                                    anchors.rightMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.isDefault ? "DEFAULT" : ""
                                    color: root.mutedColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const node = modelData;
                                        if (root.audioNodeReady(node))
                                            Pipewire.preferredDefaultAudioSink = node;
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.outputDevices.length === 0
                            text: !Pipewire.ready ? "Waiting for PipeWire..." : "No output devices available."
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                Column {
                    id: inputPage
                    visible: root.activeTab === "input"
                    width: parent.width
                    height: parent.height
                    spacing: 6

                    Column {
                        width: parent.width
                        height: 28
                        spacing: 1

                        Text {
                            text: "DEFAULT INPUT"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            width: parent.width
                            text: root.audioNodeReady(Pipewire.defaultAudioSource)
                                ? root.nodeLabel(Pipewire.defaultAudioSource)
                                : (Pipewire.ready ? "No input device selected" : "Waiting for PipeWire...")
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: inputVolumeRow
                        width: parent.width
                        height: 52

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: root.audioNodeReady(Pipewire.defaultAudioSource)
                                && Pipewire.defaultAudioSource.audio.muted
                                ? "󰍭  INPUT VOLUME" : "󰍬  INPUT VOLUME"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        Text {
                            anchors.right: inputMuteButton.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            width: 42
                            horizontalAlignment: Text.AlignRight
                            text: root.audioNodeReady(Pipewire.defaultAudioSource)
                                ? Math.round(Pipewire.defaultAudioSource.audio.volume * 100) + "%" : "--%"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }

                        Text {
                            anchors.right: inputMuteButton.left
                            anchors.rightMargin: 55
                            anchors.top: parent.top
                            width: 36
                            horizontalAlignment: Text.AlignRight
                            text: root.audioNodeReady(Pipewire.defaultAudioSource)
                                && Pipewire.defaultAudioSource.audio.muted ? "MUTED" : ""
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }

                        Rectangle {
                            id: inputMuteButton
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: 58
                            height: 20
                            radius: 0
                            color: inputMuteMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                            border.width: 1
                            border.color: "#373737"
                            opacity: root.audioNodeReady(Pipewire.defaultAudioSource) ? 1 : 0.45

                            Text {
                                anchors.centerIn: parent
                                text: root.audioNodeReady(Pipewire.defaultAudioSource)
                                    && Pipewire.defaultAudioSource.audio.muted ? "UNMUTE" : "MUTE"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: inputMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.audioNodeReady(Pipewire.defaultAudioSource)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const node = Pipewire.defaultAudioSource;
                                    if (root.audioNodeReady(node))
                                        node.audio.muted = !node.audio.muted;
                                }
                            }
                        }

                        Slider {
                            id: inputVolumeSlider
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 27
                            height: 22
                            from: 0
                            to: 1.5
                            stepSize: 0.01
                            enabled: root.audioNodeReady(Pipewire.defaultAudioSource)
                            value: enabled ? Pipewire.defaultAudioSource.audio.volume : 0
                            onMoved: {
                                const node = Pipewire.defaultAudioSource;
                                if (root.audioNodeReady(node))
                                    node.audio.volume = value;
                            }
                            background: Rectangle {
                                x: inputVolumeSlider.leftPadding
                                y: inputVolumeSlider.topPadding + inputVolumeSlider.availableHeight / 2 - height / 2
                                width: inputVolumeSlider.availableWidth
                                height: 3
                                color: "#303030"
                                Rectangle {
                                    width: inputVolumeSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#ffffff"
                                }
                            }
                            handle: Rectangle {
                                x: inputVolumeSlider.leftPadding
                                    + inputVolumeSlider.visualPosition * (inputVolumeSlider.availableWidth - width)
                                y: inputVolumeSlider.topPadding + inputVolumeSlider.availableHeight / 2 - height / 2
                                width: 6
                                height: 12
                                radius: 0
                                color: "#ffffff"
                                border.width: 1
                                border.color: "#ffffff"
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.separatorColor
                    }

                    Item {
                        width: parent.width
                        height: 17
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "AVAILABLE INPUTS"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(0, parent.height - 122)

                        ListView {
                            id: inputDeviceList
                            anchors.fill: parent
                            visible: root.inputDevices.length > 0
                            clip: true
                            spacing: 4
                            model: root.inputDevices

                            delegate: Item {
                                required property var modelData
                                width: inputDeviceList.width
                                height: 36

                                readonly property bool isDefault: Pipewire.defaultAudioSource !== null
                                    && Pipewire.defaultAudioSource !== undefined
                                    && Pipewire.defaultAudioSource.id === modelData.id

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 0
                                    color: parent.isDefault ? "#111111" : "#0c0c0c"
                                    border.width: 1
                                    border.color: parent.isDefault ? "#454545" : "#303030"
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 9
                                    anchors.right: inputDefaultLabel.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.nodeLabel(modelData)
                                    color: root.foregroundColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: inputDefaultLabel
                                    anchors.right: parent.right
                                    anchors.rightMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.isDefault ? "DEFAULT" : ""
                                    color: root.mutedColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const node = modelData;
                                        if (root.audioNodeReady(node))
                                            Pipewire.preferredDefaultAudioSource = node;
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.inputDevices.length === 0
                            text: !Pipewire.ready ? "Waiting for PipeWire..." : "No input devices available."
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                Column {
                    id: applicationsPage
                    visible: root.activeTab === "applications"
                    width: parent.width
                    height: parent.height
                    spacing: 5

                    Item {
                        width: parent.width
                        height: 18

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ACTIVE APPLICATION STREAMS"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(0, parent.height - 23)

                        ListView {
                            id: applicationList
                            anchors.fill: parent
                            visible: root.applicationStreams.length > 0
                            clip: true
                            spacing: 5
                            model: root.applicationStreams

                            delegate: Item {
                                required property var modelData
                                width: applicationList.width
                                height: 78

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 0
                                    color: "#0c0c0c"
                                    border.width: 1
                                    border.color: "#303030"
                                }

                                IconImage {
                                    id: applicationIcon
                                    x: 8
                                    y: 7
                                    width: 18
                                    height: 18
                                    source: Quickshell.iconPath(root.applicationIconName(modelData), true)
                                    asynchronous: true
                                }

                                Text {
                                    anchors.fill: applicationIcon
                                    text: ""
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    visible: applicationIcon.status !== Image.Ready
                                }

                                Text {
                                    anchors.left: applicationIcon.right
                                    anchors.leftMargin: 8
                                    anchors.right: applicationMuteButton.left
                                    anchors.rightMargin: 7
                                    anchors.top: parent.top
                                    anchors.topMargin: 7
                                    text: root.applicationName(modelData)
                                    color: root.foregroundColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.bold: false
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: applicationMuteButton
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 6
                                    width: 57
                                    height: 19
                                    radius: 0
                                    color: applicationMuteMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                                    border.width: 1
                                    border.color: "#373737"
                                    opacity: root.audioNodeReady(modelData) ? 1 : 0.45

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.audioNodeReady(modelData) && modelData.audio.muted ? "UNMUTE" : "MUTE"
                                        color: root.foregroundColor
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                    }

                                    MouseArea {
                                        id: applicationMuteMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: modelData !== null && modelData !== undefined
                                            && modelData.ready && modelData.audio !== null
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const node = modelData;
                                            if (node && node.ready && node.audio)
                                                node.audio.muted = !node.audio.muted;
                                        }
                                    }
                                }

                                Text {
                                    anchors.left: applicationIcon.right
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.top: parent.top
                                    anchors.topMargin: 26
                                    text: root.outputForStream(modelData)
                                    color: root.mutedColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }

                                Slider {
                                    id: applicationVolumeSlider
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: applicationPercent.left
                                    anchors.rightMargin: 7
                                    anchors.top: parent.top
                                    anchors.topMargin: 47
                                    height: 22
                                    from: 0
                                    to: 1.5
                                    stepSize: 0.01
                                    enabled: root.audioNodeReady(modelData)
                                    value: enabled ? modelData.audio.volume : 0
                                    onMoved: {
                                        const node = modelData;
                                        if (node && node.ready && node.audio)
                                            node.audio.volume = value;
                                    }
                                    background: Rectangle {
                                        x: applicationVolumeSlider.leftPadding
                                        y: applicationVolumeSlider.topPadding + applicationVolumeSlider.availableHeight / 2 - height / 2
                                        width: applicationVolumeSlider.availableWidth
                                        height: 3
                                        color: "#303030"
                                        Rectangle {
                                            width: applicationVolumeSlider.visualPosition * parent.width
                                            height: parent.height
                                            color: "#ffffff"
                                        }
                                    }
                                    handle: Rectangle {
                                        x: applicationVolumeSlider.leftPadding
                                            + applicationVolumeSlider.visualPosition * (applicationVolumeSlider.availableWidth - width)
                                        y: applicationVolumeSlider.topPadding + applicationVolumeSlider.availableHeight / 2 - height / 2
                                        width: 6
                                        height: 12
                                        radius: 0
                                        color: "#ffffff"
                                        border.width: 1
                                        border.color: "#ffffff"
                                    }
                                }

                                Text {
                                    id: applicationPercent
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.top: parent.top
                                    anchors.topMargin: 51
                                    width: 42
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData && modelData.audio
                                        ? Math.round(modelData.audio.volume * 100) + "%" : "--%"
                                    color: root.mutedColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.applicationStreams.length === 0
                            text: !Pipewire.ready ? "Waiting for PipeWire..." : "No active application audio streams."
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.fill: parent
                    text: root.statusMessage.length > 0 ? root.statusMessage : "PIPEWIRE AUDIO CONTROLS"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
