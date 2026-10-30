import QtQuick

Item {
    id: root

    property string glyph: ""
    property color accent: Theme.iris
    property string title: ""
    property string subtitle: ""

    default property alias trailing: trailingRow.data

    width: parent ? parent.width : 0
    height: 40

    Rectangle {
        id: badge
        width: 40
        height: 40
        radius: 14
        color: Theme.tint(root.accent, 0.18)

        Icon {
            anchors.centerIn: parent
            text: root.glyph
            color: root.accent
            font.pixelSize: 20
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: 11
        anchors.right: trailingRow.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        UiText {
            width: parent.width
            text: root.title
            font.pixelSize: 16
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        UiText {
            width: parent.width
            visible: text.length > 0
            text: root.subtitle
            color: Theme.subtle
            font.pixelSize: 11
            font.weight: Font.Normal
            elide: Text.ElideRight
        }
    }

    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
}
