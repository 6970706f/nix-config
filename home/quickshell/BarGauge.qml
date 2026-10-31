import QtQuick

Item {
    id: root

    property string glyph: ""
    property int percent: 0
    property color accent: Theme.iris

    signal clicked()

    width: 62
    height: 28

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: mouse.containsMouse ? Theme.raised : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.fast }
        }
    }

    RingGauge {
        id: ring
        x: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        value: root.percent
        accent: Theme.levelColor(root.percent, root.accent)
        thickness: 2.5

        Icon {
            anchors.centerIn: parent
            text: root.glyph
            color: ring.accent
            font.pixelSize: 11
        }
    }

    UiText {
        anchors.left: ring.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: root.percent + "%"
        font.pixelSize: 12
        font.weight: Font.DemiBold
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
