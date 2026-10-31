import QtQuick

// Tab strip whose highlight slides to the current entry.
Rectangle {
    id: root

    // Entries look like { key, label }.
    property var tabs: []
    property string current: ""
    property color accent: Theme.iris

    readonly property real tabWidth: root.tabs.length > 0 ? (root.width - 6) / root.tabs.length : 0
    readonly property int currentIndex: {
        for (let i = 0; i < root.tabs.length; i++) {
            if (root.tabs[i].key === root.current)
                return i;
        }
        return 0;
    }

    signal picked(string key)

    width: parent ? parent.width : 0
    height: 36
    radius: height / 2
    color: Theme.surface

    Rectangle {
        x: 3 + root.currentIndex * root.tabWidth
        y: 3
        width: root.tabWidth
        height: root.height - 6
        radius: height / 2
        color: root.accent

        Behavior on x {
            NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic }
        }
    }

    Row {
        x: 3
        y: 3

        Repeater {
            model: root.tabs

            delegate: Item {
                id: tab
                required property var modelData
                width: root.tabWidth
                height: root.height - 6

                UiText {
                    anchors.centerIn: parent
                    text: tab.modelData.label
                    color: root.current === tab.modelData.key
                        ? Theme.onAccent
                        : (tabMouse.containsMouse ? Theme.text : Theme.subtle)
                    font.pixelSize: 12
                    font.weight: Font.DemiBold

                    Behavior on color {
                        ColorAnimation { duration: Theme.fast }
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(tab.modelData.key)
                }
            }
        }
    }
}
