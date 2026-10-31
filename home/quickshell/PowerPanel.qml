import Quickshell
import Quickshell.Io
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null


    property bool confirmationVisible: false
    property string pendingAction: ""
    property bool actionBusy: false
    property string errorMessage: ""

    readonly property var actions: [
        { action: "lock", label: "Lock", icon: "󰌾" },
        { action: "suspend", label: "Suspend", icon: "󰤄" },
        { action: "hibernate", label: "Hibernate", icon: "󰒲" },
        { action: "logout", label: "Log out", icon: "󰍃" },
        { action: "reboot", label: "Reboot", icon: "󰜉" },
        { action: "shutdown", label: "Shut down", icon: "󰐥" }
    ]

    width: 312 + Theme.popupPadX * 2
    height: (confirmationVisible
        ? (errorMessage.length > 0 ? 232 : 206)
        : 266) + Theme.popupPadY
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

    function actionName(action) {
        switch (action) {
        case "lock": return "Lock screen";
        case "suspend": return "Suspend";
        case "hibernate": return "Hibernate";
        case "logout": return "Log out";
        case "reboot": return "Reboot";
        case "shutdown": return "Shut down";
        default: return "This action";
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

    function accentFor(action) {
        switch (action) {
        case "lock": return Theme.iris;
        case "suspend": return Theme.foam;
        case "hibernate": return Theme.mint;
        case "logout": return Theme.gold;
        case "reboot": return Theme.rose;
        default: return Theme.love;
        }
    }

    function glyphFor(action) {
        for (let i = 0; i < root.actions.length; i++) {
            if (root.actions[i].action === action)
                return root.actions[i].icon;
        }
        return Theme.icons.power;
    }

    PanelSurface {
        id: outerBorder
        window: root
        accent: root.confirmationVisible ? root.accentFor(root.pendingAction) : Theme.love

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 14

            PanelHeader {
                glyph: root.confirmationVisible ? root.glyphFor(root.pendingAction) : Theme.icons.power
                accent: root.confirmationVisible ? root.accentFor(root.pendingAction) : Theme.love
                title: root.confirmationVisible ? "Confirm action" : "Power"
                subtitle: root.actionBusy ? "Working…" : (root.confirmationVisible ? "" : "Select an action to continue")
            }

            Grid {
                id: optionsColumn
                visible: !root.confirmationVisible
                width: parent.width
                columns: 3
                spacing: 8

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: optionRow
                        required property var modelData
                        readonly property color tileAccent: root.accentFor(modelData.action)

                        width: (optionsColumn.width - optionsColumn.spacing * 2) / 3
                        height: 86
                        radius: Theme.radiusTile
                        color: optionMouse.containsMouse ? Theme.tint(tileAccent, 0.22) : Theme.surface
                        scale: optionMouse.pressed ? 0.95 : 1

                        Behavior on color {
                            ColorAnimation { duration: Theme.fast }
                        }

                        Behavior on scale {
                            NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 7

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: optionRow.modelData.icon
                                color: optionRow.tileAccent
                                font.pixelSize: 24
                            }

                            UiText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: optionRow.modelData.label
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
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
                spacing: 12

                Column {
                    width: parent.width
                    spacing: 4

                    UiText {
                        width: parent.width
                        text: root.actionName(root.pendingAction) + "?"
                        font.family: Theme.displayFont
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }

                    UiText {
                        width: parent.width
                        text: root.actionDescription(root.pendingAction)
                        color: Theme.subtle
                        font.pixelSize: 12
                        font.weight: Font.Normal
                        wrapMode: Text.WordWrap
                    }
                }

                UiText {
                    width: parent.width
                    visible: root.errorMessage.length > 0
                    text: root.errorMessage
                    color: Theme.love
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    spacing: 8

                    SoftButton {
                        width: (parent.width - parent.spacing) / 2
                        implicitHeight: 38
                        label: "Cancel"
                        enabled: !root.actionBusy
                        onClicked: root.cancelConfirmation()
                    }

                    SoftButton {
                        width: (parent.width - parent.spacing) / 2
                        implicitHeight: 38
                        label: root.actionBusy ? "Running…" : "Confirm"
                        variant: "accent"
                        accent: root.accentFor(root.pendingAction)
                        enabled: !root.actionBusy
                        onClicked: root.executePendingAction()
                    }
                }
            }
        }
    }
}
