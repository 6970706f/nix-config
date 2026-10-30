import QtQuick
import QtQuick.Controls

// Thick two-part track split by a slim handle, after Material 3 Expressive.
Slider {
    id: control

    property color accent: Theme.iris

    readonly property real handleCenter: control.visualPosition * control.availableWidth
    readonly property int handleGap: 4

    height: 26
    padding: 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0
    opacity: control.enabled ? 1 : 0.45

    background: Item {
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth
        height: 14

        Rectangle {
            width: Math.max(0, control.handleCenter - control.handleGap)
            height: parent.height
            radius: height / 2
            color: control.accent
        }

        Rectangle {
            x: control.handleCenter + control.handleGap
            width: Math.max(0, parent.width - x)
            height: parent.height
            radius: height / 2
            color: Theme.raised
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.handleCenter - width / 2
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.pressed || control.hovered ? 6 : 4
        height: control.availableHeight
        radius: width / 2
        color: Theme.text

        Behavior on width {
            NumberAnimation { duration: Theme.fast }
        }
    }
}
