import Quickshell
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    // The other bar panels, which don't know about this one: it steps aside when one opens.
    property var siblingPanels: []

    readonly property bool siblingOpen: root.siblingPanels.some(function(panel) {
        return panel.visible;
    })
    readonly property int listHeight: NotificationService.history.length > 0
        ? Math.max(1, Math.min(notificationList.contentHeight, 520))
        : 132

    // Header, do not disturb row, gaps and the card's own padding around the list.
    implicitWidth: 380 + Theme.popupPadX * 2
    implicitHeight: 40 + 14 + 48 + 14 + root.listHeight + 32 + Theme.popupPadY
    color: "transparent"
    visible: false

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

    function openPanel() {
        root.siblingPanels.forEach(function(panel) {
            if (panel.visible)
                panel.closePanel();
        });
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

    // Also runs when the PopupWindow hides itself after an outside click.
    onVisibleChanged: NotificationService.setCenterOpen(root.visible)

    onSiblingOpenChanged: {
        if (root.siblingOpen)
            root.closePanel();
    }

    Connections {
        target: NotificationService

        function onCenterToggleRequested(screenName) {
            const screen = root.anchorWindow ? root.anchorWindow.screen : null;
            const matches = screen && (screenName.length > 0
                ? screen.name === screenName
                : screen === Quickshell.screens[0]);
            if (matches)
                root.togglePanel();
        }

        // An action usually brings its app forward; don't stay on top of it.
        function onActionInvoked() {
            root.closePanel();
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    PanelSurface {
        window: root

        Column {
            anchors.fill: parent
            spacing: 14

            PanelHeader {
                glyph: {
                    if (NotificationService.doNotDisturb)
                        return Theme.icons.bellOff;
                    return NotificationService.unreadCount > 0 ? Theme.icons.bell : Theme.icons.bellOutline;
                }
                title: "Notifications"
                subtitle: {
                    if (NotificationService.unreadCount > 0)
                        return NotificationService.unreadCount + " unread";
                    const total = NotificationService.history.length;
                    if (total === 0)
                        return "You're all caught up";
                    return total === 1 ? "1 notification" : total + " notifications";
                }

                SoftButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: NotificationService.history.length > 0
                    variant: "ghost"
                    glyph: Theme.icons.trash
                    label: "Clear all"
                    onClicked: NotificationService.clearAll()
                }
            }

            Rectangle {
                width: parent.width
                height: 48
                radius: Theme.radiusTile
                color: Theme.surface

                Icon {
                    id: doNotDisturbIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: NotificationService.doNotDisturb ? Theme.icons.bellOff : Theme.icons.bellOutline
                    color: NotificationService.doNotDisturb ? Theme.text : Theme.subtle
                    font.pixelSize: 16
                }

                Column {
                    anchors.left: doNotDisturbIcon.right
                    anchors.leftMargin: 10
                    anchors.right: doNotDisturbSwitch.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    UiText {
                        width: parent.width
                        text: "Do not disturb"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    UiText {
                        width: parent.width
                        text: NotificationService.doNotDisturb ? "Only critical pop-ups" : "All pop-ups"
                        color: Theme.subtle
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                SoftSwitch {
                    id: doNotDisturbSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    checked: NotificationService.doNotDisturb
                    onClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
                }
            }

            Item {
                width: parent.width
                height: root.listHeight

                Column {
                    anchors.centerIn: parent
                    visible: NotificationService.history.length === 0
                    spacing: 8

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Theme.icons.bellOutline
                        color: Theme.muted
                        font.pixelSize: 32
                    }

                    UiText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No notifications"
                        color: Theme.subtle
                        font.pixelSize: 12
                    }
                }

                ListView {
                    id: notificationList
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel {
                        objectProp: "key"
                        values: NotificationService.history
                    }

                    delegate: Rectangle {
                        id: notificationRow

                        required property var modelData

                        width: notificationList.width
                        height: rowCard.height + 20
                        radius: Theme.radiusTile
                        color: rowCard.hovered ? Theme.raised : Theme.surface
                        border.width: modelData.critical ? 1 : 0
                        border.color: Theme.stroke

                        Behavior on color {
                            ColorAnimation { duration: Theme.fast }
                        }

                        NotificationCard {
                            id: rowCard
                            x: 10
                            y: 10
                            width: parent.width - 20
                            entry: notificationRow.modelData
                            showUnread: true
                            expandable: true
                            onCloseRequested: NotificationService.dismiss(notificationRow.modelData)
                        }
                    }

                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast; easing.type: Easing.OutCubic }
                    }

                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: Theme.normal; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
