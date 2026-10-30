import QtQuick

Rectangle {
    id: root

    property string label: ""
    property string glyph: ""
    // One of: tonal, accent, ghost, danger.
    property string variant: "tonal"
    property color accent: Theme.iris
    property int fontSize: 12

    readonly property bool hovered: mouse.containsMouse
    readonly property color contentColor: {
        if (root.variant === "accent")
            return Theme.onAccent;
        if (root.variant === "danger")
            return Theme.love;
        return Theme.text;
    }

    signal clicked()

    implicitWidth: content.implicitWidth + (root.label.length > 0 ? 26 : 0)
    implicitHeight: 32
    width: root.label.length > 0 ? implicitWidth : implicitHeight
    height: implicitHeight
    radius: height / 2
    opacity: root.enabled ? 1 : 0.45
    scale: mouse.pressed ? 0.95 : 1

    color: {
        if (root.variant === "accent")
            return root.hovered ? Qt.darker(root.accent, 1.18) : root.accent;
        if (root.variant === "danger")
            return Theme.tint(Theme.love, root.hovered ? 0.32 : 0.18);
        if (root.variant === "ghost")
            return root.hovered ? Theme.raised : "transparent";
        return root.hovered ? Theme.hover : Theme.raised;
    }

    Behavior on color {
        ColorAnimation { duration: Theme.fast }
    }

    Behavior on scale {
        NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            text: root.glyph
            color: root.contentColor
            font.pixelSize: root.fontSize + 3
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label.length > 0
            text: root.label
            color: root.contentColor
            font.pixelSize: root.fontSize
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.clicked()
    }
}
