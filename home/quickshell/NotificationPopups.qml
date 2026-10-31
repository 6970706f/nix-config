import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// Pop-ups stack in the bottom right corner of the focused screen.
Scope {
    id: root

    readonly property int cardWidth: 360
    readonly property int cardPadding: 12
    // Cards reserve shadow room on every side; this overlaps it back to a normal gap.
    readonly property int cardSpacing: 8 - Theme.popupPadY

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popupWindow

            required property var modelData
            screen: modelData

            readonly property bool active: {
                const monitor = Hyprland.focusedMonitor;
                return monitor
                    ? monitor.name === popupWindow.modelData.name
                    : popupWindow.modelData === Quickshell.screens[0];
            }
            readonly property bool hasPopups: active && NotificationService.popups.length > 0

            // The window spans the screen's height, so resizing never interrupts an animation;
            // only the cards take input.
            anchors {
                top: true
                right: true
                bottom: true
            }
            margins.top: Theme.barHeight
            implicitWidth: root.cardWidth + Theme.popupPadX * 2
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            visible: hasPopups || hideDelay.running

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region { item: inputArea }

            // Lets the last card finish animating out before the window goes away.
            onHasPopupsChanged: {
                if (!hasPopups)
                    hideDelay.restart();
            }

            Timer {
                id: hideDelay
                interval: Theme.normal
            }

            Item {
                id: inputArea
                x: Theme.popupPadX
                y: popupWindow.height - Theme.popupPadBottom - height
                width: root.cardWidth
                height: Math.max(0, popupList.contentHeight - Theme.popupPadY)
            }

            ListView {
                id: popupList
                anchors.fill: parent
                interactive: false
                verticalLayoutDirection: ListView.BottomToTop
                spacing: root.cardSpacing
                model: ScriptModel {
                    objectProp: "key"
                    values: popupWindow.active ? NotificationService.popups : []
                }

                delegate: Item {
                    id: popupItem

                    required property var modelData

                    width: popupList.width
                    height: card.implicitHeight + root.cardPadding * 2 + Theme.popupPadY

                    PanelSurface {
                        padding: root.cardPadding
                        accent: popupItem.modelData.critical ? Theme.love : Theme.iris

                        NotificationCard {
                            id: card
                            entry: popupItem.modelData
                            onCloseRequested: NotificationService.hidePopup(popupItem.modelData)
                            onPlainClicked: NotificationService.hidePopup(popupItem.modelData)
                            onHoveredChanged: popupItem.modelData.hovered = hovered
                        }
                    }
                }

                add: Transition {
                    NumberAnimation { property: "x"; from: 40; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
                }

                remove: Transition {
                    NumberAnimation { property: "x"; to: 40; duration: Theme.fast; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast; easing.type: Easing.InCubic }
                }

                // Displacing a card cancels its add transition, so this has to finish that job.
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
