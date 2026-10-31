import Quickshell
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null
    property int batteryPercent: 0
    property string batteryStatus: "Unknown"
    property string batteryModel: "Battery"

    readonly property color batteryAccent: root.batteryStatus === "Charging"
        ? Theme.mint
        : (root.batteryPercent <= 15 ? Theme.love : (root.batteryPercent <= 30 ? Theme.gold : Theme.mint))

    width: 290 + Theme.popupPadX * 2
    height: 186 + Theme.popupPadY
    color: "transparent"
    visible: false

    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 0;

        // Re-read the anchor on open: bar tabs shift as their content changes.
        root.visible;
        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const maximumX = Math.max(0, root.anchorWindow.width - root.width);
        return Math.max(0, Math.min(
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

    PanelSurface {
        window: root
        accent: root.batteryAccent

        Column {
            anchors.fill: parent
            spacing: 14

            PanelHeader {
                glyph: root.batteryStatus === "Charging" ? Theme.icons.batteryCharging : Theme.icons.battery
                accent: root.batteryAccent
                title: "Battery"
                subtitle: root.batteryModel
            }

            Row {
                spacing: 8

                UiText {
                    id: percentLabel
                    text: root.batteryPercent + "%"
                    font.family: Theme.displayFont
                    font.pixelSize: 44
                    font.weight: Font.Bold
                }

                UiText {
                    anchors.baseline: percentLabel.baseline
                    text: root.batteryStatus
                    color: root.batteryAccent
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            MeterBar {
                width: parent.width
                height: 14
                value: root.batteryPercent / 100
                accent: root.batteryAccent
            }
        }
    }
}
