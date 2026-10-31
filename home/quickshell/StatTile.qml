import QtQuick

Rectangle {
    id: root

    property string label: ""
    property string value: ""

    height: 58
    radius: Theme.radiusTile
    color: Theme.surface

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        UiText {
            width: parent.width
            text: root.value
            font.pixelSize: 15
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        UiText {
            width: parent.width
            text: root.label
            color: Theme.subtle
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
