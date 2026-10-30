import QtQuick
import QtQuick.Effects

// The card every popup is drawn on: shadow, accent wash and a short entrance.
Item {
    id: root

    property var window: null
    property color accent: Theme.iris
    property int padding: 16

    default property alias content: body.data

    anchors.fill: parent
    anchors.leftMargin: Theme.popupPadX
    anchors.rightMargin: Theme.popupPadX
    anchors.topMargin: Theme.popupPadTop
    anchors.bottomMargin: Theme.popupPadBottom
    focus: root.window ? root.window.visible : false

    readonly property bool shown: root.window ? root.window.visible : false

    onShownChanged: {
        if (root.shown)
            entrance.restart();
    }

    transform: Translate { id: slide }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: slide; property: "y"; from: -10; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 26
        offset.y: 8
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusCard
        border.width: 1
        border.color: Theme.stroke

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.tint(Theme.base, Theme.tint(root.accent, 0.12)) }
            GradientStop { position: 0.4; color: Theme.base }
        }
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
