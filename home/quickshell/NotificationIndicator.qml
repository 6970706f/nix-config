import QtQuick

// Bar button for the notification center, with a badge counting what is still unread.
Item {
    id: root

    readonly property int unreadCount: NotificationService.unreadCount

    signal clicked()

    width: button.width
    height: button.height

    BarIconButton {
        id: button
        active: NotificationService.history.length > 0
        glyph: {
            if (NotificationService.doNotDisturb)
                return Theme.icons.bellOff;
            return root.unreadCount > 0 ? Theme.icons.bell : Theme.icons.bellOutline;
        }
        onClicked: root.clicked()
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: -3
        anchors.top: parent.top
        anchors.topMargin: -2
        width: Math.max(14, badgeLabel.implicitWidth + 7)
        height: 14
        radius: height / 2
        color: Theme.love
        border.width: 1
        border.color: Theme.base
        scale: root.unreadCount > 0 ? 1 : 0

        Behavior on scale {
            NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack }
        }

        UiText {
            id: badgeLabel
            anchors.centerIn: parent
            text: root.unreadCount > 9 ? "9+" : root.unreadCount
            color: Theme.onAccent
            font.pixelSize: 9
            font.weight: Font.Bold
        }
    }
}
