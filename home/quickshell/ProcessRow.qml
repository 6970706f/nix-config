import QtQuick

Rectangle {
    id: root

    property string pid: ""
    property string name: ""
    property real percent: 0
    property string memory: ""
    property color accent: Theme.iris

    width: parent ? parent.width : 0
    height: 36
    radius: 12
    color: rowHover.hovered ? Theme.surface : "transparent"

    HoverHandler {
        id: rowHover
    }

    UiText {
        id: percentLabel
        anchors.right: memoryLabel.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 46
        text: root.percent.toFixed(1) + "%"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
    }

    UiText {
        id: memoryLabel
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 62
        text: root.memory
        color: Theme.subtle
        font.pixelSize: 11
        horizontalAlignment: Text.AlignRight
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: percentLabel.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Item {
            width: parent.width
            height: 15

            UiText {
                anchors.left: parent.left
                anchors.right: pidLabel.left
                anchors.rightMargin: 6
                height: parent.height
                text: root.name
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            UiText {
                id: pidLabel
                anchors.right: parent.right
                height: parent.height
                text: root.pid
                color: Theme.muted
                font.pixelSize: 10
            }
        }

        MeterBar {
            width: parent.width
            height: 4
            value: root.percent / 100
            accent: root.accent
        }
    }
}
