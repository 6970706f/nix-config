import QtQuick

Rectangle {
    id: root

    property bool checked: false
    property color accent: Theme.iris

    signal clicked()

    width: 46
    height: 26
    radius: height / 2
    color: root.checked ? root.accent : Theme.raised
    opacity: root.enabled ? 1 : 0.45

    Behavior on color {
        ColorAnimation { duration: Theme.normal }
    }

    Rectangle {
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        width: mouse.pressed ? 24 : 20
        height: 20
        radius: 10
        color: root.checked ? Theme.onAccent : Theme.subtle

        Behavior on x {
            NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack }
        }

        Behavior on width {
            NumberAnimation { duration: Theme.fast }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.clicked()
    }
}
