import Quickshell.Widgets
import QtQuick

// The contents of a notification, shared by the pop-ups and the notification center.
Item {
    id: root

    required property var entry
    property bool showUnread: false
    property bool expandable: false
    property int bodyLines: 3

    readonly property bool hovered: hover.hovered
    property bool expanded: false

    signal closeRequested()
    signal plainClicked()

    width: parent ? parent.width : 0
    implicitHeight: content.implicitHeight
    height: implicitHeight

    // Positioners settle on the next frame, too late for a ListView placing this delegate.
    Component.onCompleted: {
        actionFlow.forceLayout();
        content.forceLayout();
    }

    HoverHandler {
        id: hover
    }

    // Sits below the content so the buttons get their clicks first.
    MouseArea {
        anchors.fill: parent
        cursorShape: root.entry.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (root.entry.defaultAction)
                NotificationService.invokeAction(root.entry, root.entry.defaultAction);
            else
                root.plainClicked();
        }
    }

    Column {
        id: content
        width: parent.width
        spacing: 8

        Item {
            width: parent.width
            height: Math.max(badge.height, heading.implicitHeight)

            ClippingRectangle {
                id: badge
                width: 34
                height: 34
                radius: 11
                color: root.entry.critical ? Theme.love : Theme.raised

                Image {
                    id: picture
                    anchors.centerIn: parent
                    width: root.entry.hasPicture ? parent.width : 22
                    height: width
                    source: root.entry.iconSource
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    fillMode: root.entry.hasPicture ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: picture.status !== Image.Ready
                    text: Theme.icons.bell
                    color: root.entry.critical ? Theme.onAccent : Theme.subtle
                }
            }

            Column {
                id: heading
                anchors.left: badge.right
                anchors.leftMargin: 10
                anchors.right: trailing.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Row {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showUnread && !root.entry.read
                        width: 6
                        height: 6
                        radius: 3
                        color: Theme.love
                    }

                    UiText {
                        width: parent.width - (root.showUnread && !root.entry.read ? 12 : 0)
                        text: root.entry.title
                        textFormat: Text.PlainText
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }

                UiText {
                    width: parent.width
                    text: root.entry.appLabel + " · " + NotificationService.timeLabel(root.entry.time)
                    textFormat: Text.PlainText
                    color: Theme.subtle
                    font.pixelSize: 11
                    font.weight: Font.Normal
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            Row {
                id: trailing
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 2

                SoftButton {
                    visible: root.expandable && (bodyText.truncated || root.expanded)
                    implicitHeight: 24
                    variant: "ghost"
                    glyph: root.expanded ? Theme.icons.chevronUp : Theme.icons.chevronDown
                    onClicked: root.expanded = !root.expanded
                }

                SoftButton {
                    implicitHeight: 24
                    variant: "ghost"
                    glyph: Theme.icons.close
                    onClicked: root.closeRequested()
                }
            }
        }

        UiText {
            id: bodyText
            width: parent.width
            visible: text.length > 0
            text: root.entry.displayBody
            textFormat: Text.StyledText
            color: Theme.subtle
            linkColor: Theme.text
            font.pixelSize: 12
            font.weight: Font.Normal
            wrapMode: Text.Wrap
            maximumLineCount: root.expanded ? 1000 : root.bodyLines
            elide: Text.ElideRight
        }

        Flow {
            id: actionFlow
            width: parent.width
            visible: root.entry.actions.length > 0
            spacing: 6

            Repeater {
                model: root.entry.actions

                delegate: SoftButton {
                    required property var modelData

                    implicitHeight: 28
                    fontSize: 11
                    label: modelData.text.length > 36 ? modelData.text.slice(0, 35) + "…" : modelData.text
                    onClicked: NotificationService.invokeAction(root.entry, modelData)
                }
            }
        }
    }
}
