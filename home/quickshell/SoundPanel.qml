import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null


    property string activeTab: "output"
    property string statusMessage: ""

    width: 390 + Theme.popupPadX * 2
    height: (activeTab === "applications" ? 470 : 430) + Theme.popupPadY
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 0;

        // Re-read the anchor on open: bar tabs shift as their content changes.
        root.visible;
        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const maximumX = Math.max(0, root.anchorWindow.width - root.width);
        return Math.max(0, Math.min(
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

    // Output and input pages differ only in the node and device list they show.
    component DevicePage: Column {
        id: page

        required property var node
        required property var devices
        property string currentLabel: ""
        property string emptyNodeLabel: ""
        property string listLabel: ""
        property string emptyListLabel: ""
        property string volumeGlyph: ""
        property string mutedGlyph: ""

        signal pick(var device)

        readonly property bool ready: root.audioNodeReady(page.node)
        readonly property bool muted: page.ready && page.node.audio.muted

        spacing: 10

        Rectangle {
            width: parent.width
            height: 108
            radius: 18
            color: Theme.surface

            Icon {
                id: heroIcon
                x: 14
                y: 14
                width: 22
                text: page.muted ? page.mutedGlyph : page.volumeGlyph
                color: page.muted ? Theme.muted : Theme.rose
                font.pixelSize: 20
            }

            Column {
                anchors.left: heroIcon.right
                anchors.leftMargin: 10
                anchors.right: heroMute.left
                anchors.rightMargin: 8
                y: 10
                spacing: 0

                UiText {
                    width: parent.width
                    text: page.currentLabel
                    color: Theme.subtle
                    font.pixelSize: 10
                }

                UiText {
                    width: parent.width
                    text: page.ready
                        ? root.nodeLabel(page.node)
                        : (Pipewire.ready ? page.emptyNodeLabel : "Waiting for PipeWire...")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            SoftButton {
                id: heroMute
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 10
                label: page.muted ? "Unmute" : "Mute"
                variant: page.muted ? "danger" : "tonal"
                fontSize: 11
                enabled: page.ready
                onClicked: {
                    const node = page.node;
                    if (root.audioNodeReady(node))
                        node.audio.muted = !node.audio.muted;
                }
            }

            UiText {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 42
                text: page.ready ? Math.round(page.node.audio.volume * 100) + "%" : "--%"
                font.family: Theme.displayFont
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            SoftSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 12
                from: 0
                to: 1.5
                stepSize: 0.01
                accent: Theme.rose
                enabled: page.ready
                value: enabled ? page.node.audio.volume : 0
                onMoved: {
                    const node = page.node;
                    if (root.audioNodeReady(node))
                        node.audio.volume = value;
                }
            }
        }

        UiText {
            height: 16
            text: page.listLabel
            color: Theme.subtle
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Item {
            width: parent.width
            height: Math.max(0, parent.height - 108 - 16 - parent.spacing * 2)

            ListView {
                id: deviceList
                anchors.fill: parent
                visible: page.devices.length > 0
                clip: true
                spacing: 4
                model: page.devices

                delegate: Rectangle {
                    id: deviceRow
                    required property var modelData
                    width: deviceList.width
                    height: 42
                    radius: 14

                    readonly property bool isDefault: page.node !== null
                        && page.node !== undefined
                        && page.node.id === modelData.id

                    color: isDefault
                        ? Theme.tint(Theme.rose, 0.16)
                        : (deviceMouse.containsMouse ? Theme.surface : "transparent")

                    Behavior on color {
                        ColorAnimation { duration: Theme.fast }
                    }

                    Rectangle {
                        id: radioDot
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 9
                        color: deviceRow.isDefault ? Theme.rose : Theme.raised

                        Icon {
                            anchors.centerIn: parent
                            visible: deviceRow.isDefault
                            text: Theme.icons.check
                            color: Theme.onAccent
                            font.pixelSize: 12
                        }
                    }

                    UiText {
                        anchors.left: radioDot.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.nodeLabel(deviceRow.modelData)
                        font.pixelSize: 12
                        font.weight: deviceRow.isDefault ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: deviceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const node = deviceRow.modelData;
                            if (root.audioNodeReady(node))
                                page.pick(node);
                        }
                    }
                }
            }

            UiText {
                anchors.centerIn: parent
                visible: page.devices.length === 0
                text: !Pipewire.ready ? "Waiting for PipeWire..." : page.emptyListLabel
                color: Theme.subtle
                font.pixelSize: 12
            }
        }
    }

    PanelSurface {
        id: outerBorder
        window: root
        accent: Theme.rose

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 12

            PanelHeader {
                glyph: Theme.icons.volumeHigh
                accent: Theme.rose
                title: "Sound"
                subtitle: root.statusMessage.length > 0 ? root.statusMessage : "PipeWire audio controls"

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusLabel.charAt(0) + root.statusLabel.slice(1).toLowerCase()
                    color: root.statusLabel === "READY" ? Theme.mint : Theme.subtle
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            SegmentTabs {
                id: tabBar
                accent: Theme.rose
                current: root.activeTab
                tabs: [
                    { key: "output", label: "Output" },
                    { key: "input", label: "Input" },
                    { key: "applications", label: "Applications" }
                ]
                onPicked: function(key) { root.activeTab = key; }
            }

            Item {
                id: pageArea
                width: parent.width
                height: parent.height - 40 - tabBar.height - parent.spacing * 2

                DevicePage {
                    id: outputPage
                    visible: root.activeTab === "output"
                    width: parent.width
                    height: parent.height
                    node: Pipewire.defaultAudioSink
                    devices: root.outputDevices
                    currentLabel: "Default output"
                    emptyNodeLabel: "No output device selected"
                    listLabel: "Available outputs"
                    emptyListLabel: "No output devices available."
                    volumeGlyph: Theme.icons.volumeHigh
                    mutedGlyph: Theme.icons.volumeOff
                    onPick: function(device) { Pipewire.preferredDefaultAudioSink = device; }
                }

                DevicePage {
                    id: inputPage
                    visible: root.activeTab === "input"
                    width: parent.width
                    height: parent.height
                    node: Pipewire.defaultAudioSource
                    devices: root.inputDevices
                    currentLabel: "Default input"
                    emptyNodeLabel: "No input device selected"
                    listLabel: "Available inputs"
                    emptyListLabel: "No input devices available."
                    volumeGlyph: Theme.icons.mic
                    mutedGlyph: Theme.icons.micOff
                    onPick: function(device) { Pipewire.preferredDefaultAudioSource = device; }
                }

                Item {
                    id: applicationsPage
                    visible: root.activeTab === "applications"
                    anchors.fill: parent

                    ListView {
                        id: applicationList
                        anchors.fill: parent
                        visible: root.applicationStreams.length > 0
                        clip: true
                        spacing: 8
                        model: root.applicationStreams

                        delegate: Rectangle {
                            required property var modelData
                            width: applicationList.width
                            height: 92
                            radius: Theme.radiusTile
                            color: Theme.surface

                            Rectangle {
                                id: applicationBadge
                                x: 10
                                y: 10
                                width: 34
                                height: 34
                                radius: 11
                                color: Theme.raised

                                IconImage {
                                    id: applicationIcon
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: Quickshell.iconPath(root.applicationIconName(modelData), true)
                                    asynchronous: true
                                }

                                Icon {
                                    anchors.centerIn: parent
                                    text: Theme.icons.musicNote
                                    color: Theme.rose
                                    visible: applicationIcon.status !== Image.Ready
                                }
                            }

                            Column {
                                anchors.left: applicationBadge.right
                                anchors.leftMargin: 10
                                anchors.right: applicationMuteButton.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: applicationBadge.verticalCenter
                                spacing: 1

                                UiText {
                                    width: parent.width
                                    text: root.applicationName(modelData)
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                UiText {
                                    width: parent.width
                                    text: root.outputForStream(modelData)
                                    color: Theme.subtle
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            SoftButton {
                                id: applicationMuteButton
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                y: 11
                                label: root.audioNodeReady(modelData) && modelData.audio.muted ? "Unmute" : "Mute"
                                variant: root.audioNodeReady(modelData) && modelData.audio.muted ? "danger" : "tonal"
                                fontSize: 11
                                enabled: modelData !== null && modelData !== undefined
                                    && modelData.ready && modelData.audio !== null
                                onClicked: {
                                    const node = modelData;
                                    if (node && node.ready && node.audio)
                                        node.audio.muted = !node.audio.muted;
                                }
                            }

                            SoftSlider {
                                id: applicationVolumeSlider
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: applicationPercent.left
                                anchors.rightMargin: 8
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 10
                                from: 0
                                to: 1.5
                                stepSize: 0.01
                                accent: Theme.rose
                                enabled: root.audioNodeReady(modelData)
                                value: enabled ? modelData.audio.volume : 0
                                onMoved: {
                                    const node = modelData;
                                    if (node && node.ready && node.audio)
                                        node.audio.volume = value;
                                }
                            }

                            UiText {
                                id: applicationPercent
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: applicationVolumeSlider.verticalCenter
                                width: 36
                                horizontalAlignment: Text.AlignRight
                                text: modelData && modelData.audio
                                    ? Math.round(modelData.audio.volume * 100) + "%" : "--%"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    UiText {
                        anchors.centerIn: parent
                        visible: root.applicationStreams.length === 0
                        text: !Pipewire.ready ? "Waiting for PipeWire..." : "No active application audio streams."
                        color: Theme.subtle
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
