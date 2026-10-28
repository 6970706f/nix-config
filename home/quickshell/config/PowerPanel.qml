import Quickshell
import Quickshell.Io
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color borderColor: "#ffffff"
    readonly property color separatorColor: "#303030"
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"

    property bool confirmationVisible: false
    property string pendingAction: ""
    property bool actionBusy: false
    property string errorMessage: ""

    readonly property var actions: [
        { action: "lock", label: "LOCK SCREEN", icon: "󰌾" },
        { action: "suspend", label: "SUSPEND", icon: "󰤄" },
        { action: "hibernate", label: "HIBERNATE", icon: "󰒲" },
        { action: "logout", label: "LOG OUT", icon: "󰍃" },
        { action: "reboot", label: "REBOOT", icon: "󰜉" },
        { action: "shutdown", label: "SHUT DOWN", icon: "󰐥" }
    ]

    width: 260
    height: confirmationVisible
        ? (errorMessage.length > 0 ? 232 : 205)
        : 282
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

    function actionName(action) {
        switch (action) {
        case "lock": return "LOCK SCREEN";
        case "suspend": return "SUSPEND";
        case "hibernate": return "HIBERNATE";
        case "logout": return "LOG OUT";
        case "reboot": return "REBOOT";
        case "shutdown": return "SHUT DOWN";
        default: return "THIS ACTION";
        }
    }

    function actionDescription(action) {
        switch (action) {
        case "lock": return "Lock the current session.";
        case "suspend": return "Sleep until you wake the device.";
        case "hibernate": return "Requires hibernation support configured in the system.";
        case "logout": return "Close the current Hyprland session.";
        case "reboot": return "Restart the computer.";
        case "shutdown": return "Power off the computer.";
        default: return "The current session may be interrupted.";
        }
    }

    function commandForAction(action) {
        switch (action) {
        case "lock": return ["hyprlock"];
        case "suspend": return ["systemctl", "suspend"];
        case "hibernate": return ["systemctl", "hibernate"];
        case "logout": return ["hyprctl", "dispatch", "exit"];
        case "reboot": return ["systemctl", "reboot"];
        case "shutdown": return ["systemctl", "poweroff"];
        default: return [];
        }
    }

    function openPanel() {
        confirmationVisible = false;
        pendingAction = "";
        errorMessage = "";
        visible = true;
    }

    // Also run cleanup when PopupWindow hides itself after an outside click.
    onVisibleChanged: {
        if (!root.visible) {
            root.confirmationVisible = false;
            root.errorMessage = "";
            if (!root.actionBusy)
                root.pendingAction = "";
        }
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

    function requestConfirmation(action) {
        if (actionBusy)
            return;
        pendingAction = action;
        errorMessage = "";
        confirmationVisible = true;
    }

    function cancelConfirmation() {
        confirmationVisible = false;
        pendingAction = "";
        errorMessage = "";
    }

    function executePendingAction() {
        if (actionBusy || commandForAction(pendingAction).length === 0)
            return;

        errorMessage = "";
        actionBusy = true;
        actionProcess.running = true;
    }

    Process {
        id: actionProcess
        command: root.commandForAction(root.pendingAction)

        stdout: StdioCollector {
            id: actionOutput
        }

        stderr: StdioCollector {
            id: actionErrors
        }

        onExited: function(exitCode, exitStatus) {
            root.actionBusy = false;
            if (exitCode === 0) {
                root.errorMessage = "";
                root.closePanel();
            } else {
                const details = String(actionErrors.text || actionOutput.text || "").trim();
                root.errorMessage = details.length > 0
                    ? details.split(/\r?\n/)[0]
                    : "The command failed. Check system permissions and configuration.";
                if (root.visible)
                    root.confirmationVisible = true;
                else
                    root.pendingAction = "";
            }
        }
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
        border.color: root.borderColor

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 7

            Item {
                width: parent.width
                height: 26

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.confirmationVisible ? "CONFIRM ACTION" : "POWER OPTIONS"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.bold: false
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.actionBusy ? "WORKING" : "SYSTEM"
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

            Column {
                id: optionsColumn
                visible: !root.confirmationVisible
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: optionRow
                        required property var modelData
                        width: optionsColumn.width
                        height: 28
                        color: optionMouse.containsMouse ? "#1c1c1c" : "#080808"
                        border.width: 1
                        border.color: "#303030"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: optionRow.modelData.icon
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 34
                            anchors.right: arrowLabel.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: optionRow.modelData.label
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                            elide: Text.ElideRight
                        }

                        Text {
                            id: arrowLabel
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰅂"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: optionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            enabled: !root.actionBusy
                            onClicked: root.requestConfirmation(optionRow.modelData.action)
                        }
                    }
                }
            }

            Column {
                visible: root.confirmationVisible
                width: parent.width
                spacing: 8

                Item {
                    width: parent.width
                    height: 54

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: root.actionName(root.pendingAction) + "?"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.bold: false
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: root.actionDescription(root.pendingAction)
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    width: parent.width
                    visible: root.errorMessage.length > 0
                    text: root.errorMessage
                    color: "#ff7777"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 7

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: parent.height
                        color: cancelMouse.containsMouse ? "#1c1c1c" : "#080808"
                        border.width: 1
                        border.color: "#373737"

                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            enabled: !root.actionBusy
                            onClicked: root.cancelConfirmation()
                        }
                    }

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: parent.height
                        color: confirmMouse.containsMouse ? "#242424" : "#111111"
                        border.width: 1
                        border.color: "#ffffff"

                        Text {
                            anchors.centerIn: parent
                            text: root.actionBusy ? "RUNNING..." : "CONFIRM"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        MouseArea {
                            id: confirmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            enabled: !root.actionBusy
                            onClicked: root.executePendingAction()
                        }
                    }
                }
            }

            Text {
                visible: !root.confirmationVisible
                width: parent.width
                text: "SELECT AN ACTION TO CONTINUE"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
