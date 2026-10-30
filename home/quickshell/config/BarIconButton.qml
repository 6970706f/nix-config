import QtQuick

Item {
    id: root

    property string glyph: ""
    property color accent: Theme.iris
    property bool active: true

    signal clicked()

    width: 28
    height: 28

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: mouse.containsMouse
            ? Theme.tint(root.accent, 0.3)
            : (root.active ? Theme.tint(root.accent, 0.14) : "transparent")

        Behavior on color {
            ColorAnimation { duration: Theme.fast }
        }
    }

    Icon {
        anchors.centerIn: parent
        text: root.glyph
        color: root.active || mouse.containsMouse ? root.accent : Theme.muted
        font.pixelSize: 15
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.clicked()
    }
}
