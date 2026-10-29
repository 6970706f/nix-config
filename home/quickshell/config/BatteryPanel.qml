import Quickshell
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null
    property int batteryPercent: 0
    property string batteryStatus: "Unknown"
    property string batteryModel: "Battery"

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color separatorColor: "#303030"
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"

    width: 270
    height: 174
    color: "transparent"
    visible: false

    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + 8 : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 8;

        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const minimumX = root.anchorWindow.width >= root.width + 16 ? 8 : 0;
        const maximumX = Math.max(minimumX, root.anchorWindow.width - root.width - minimumX);
        return Math.max(minimumX, Math.min(
            point.x + root.anchorItem.width / 2 - root.width / 2,
            maximumX
        ));
    }

    function openPanel() { visible = true; }
    function closePanel() { visible = false; }
    function togglePanel() {
        if (visible) closePanel();
        else openPanel();
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    Rectangle {
        anchors.fill: parent
        color: root.panelColor
        border.width: 1
        border.color: root.foregroundColor

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Row {
                width: parent.width
                height: 22

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BATTERY"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryStatus.toUpperCase()
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Row {
                width: parent.width
                height: 36
                spacing: 10

                Text {
                    text: "󰁹"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 25
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.batteryPercent + "%"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: parent.width
                height: 3
                color: root.separatorColor

                Rectangle {
                    width: parent.width * root.batteryPercent / 100
                    height: parent.height
                    color: root.foregroundColor
                }
            }

            Text {
                width: parent.width
                text: root.batteryModel
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }
}
