import QtQuick

Rectangle {
    id: root

    // Fill fraction between 0 and 1.
    property real value: 0
    property color accent: Theme.iris

    height: 6
    radius: height / 2
    color: Theme.raised

    Rectangle {
        width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.value)))
        height: parent.height
        radius: parent.radius
        color: root.accent
        visible: root.value > 0

        Behavior on width {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
    }
}
