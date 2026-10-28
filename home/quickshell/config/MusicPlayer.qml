import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Controls

Item {
    id: root

    // Styling and window anchoring are supplied by the existing bar.
    property color foregroundColor: "#ffffff"
    property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"
    property var anchorWindow: null

    signal closeOtherPanelsRequested()

    property int volumePercent: 35

    readonly property var spotifastPlayer: Mpris.players.values.find(function(player) {
        const dbusName = String(player.dbusName || "").toLowerCase();
        const identity = String(player.identity || "").toLowerCase();
        const desktopEntry = String(player.desktopEntry || "").toLowerCase();

        return dbusName.indexOf("spotifast") !== -1
            || identity.indexOf("spotifast") !== -1
            || desktopEntry.indexOf("spotifast") !== -1;
    }) || null

    readonly property bool trackAvailable: root.spotifastPlayer !== null
        && String(root.spotifastPlayer.trackTitle || "").trim().length > 0
    readonly property bool isPlaying: root.spotifastPlayer !== null
        && root.spotifastPlayer.isPlaying

    height: 24
    clip: true
    visible: root.trackAvailable && width >= 130

    readonly property int panelWidth: 352
    readonly property int panelLeft: {
        if (!root.anchorWindow)
            return 8;

        const point = barContent.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const minimumX = root.anchorWindow.width >= root.panelWidth + 16 ? 8 : 0;
        const maximumX = Math.max(minimumX, root.anchorWindow.width - root.panelWidth - minimumX);
        return Math.max(minimumX, Math.min(
            point.x + barContent.width / 2 - root.panelWidth / 2,
            maximumX
        ));
    }

    function openPanel() {
        if (!root.trackAvailable)
            return;
        root.closeOtherPanelsRequested();
        playerPanel.visible = true;
    }

    function closePanel() {
        playerPanel.visible = false;
    }

    function togglePanel() {
        if (playerPanel.visible)
            root.closePanel();
        else
            root.openPanel();
    }

    function runPrevious() {
        const player = root.spotifastPlayer;
        if (!player)
            return;
        if (player.canGoPrevious)
            player.previous();
        else if (!previousFallback.running)
            previousFallback.running = true;
    }

    function runPlayPause() {
        const player = root.spotifastPlayer;
        if (!player)
            return;
        if (player.canTogglePlaying)
            player.togglePlaying();
        else if (!playPauseFallback.running)
            playPauseFallback.running = true;
    }

    function runNext() {
        const player = root.spotifastPlayer;
        if (!player)
            return;
        if (player.canGoNext)
            player.next();
        else if (!nextFallback.running)
            nextFallback.running = true;
    }

    function refreshVolume() {
        if (!readNowPlaying.running)
            readNowPlaying.running = true;
    }

    function parseVolume(rawOutput) {
        const fields = String(rawOutput || "").trim().split("\t");
        if (fields.length < 7)
            return;

        const parsed = Number(fields[6]);
        if (Number.isFinite(parsed))
            root.volumePercent = Math.max(0, Math.min(100, Math.round(parsed)));
    }

    function applyVolume(value) {
        const percent = Math.max(0, Math.min(100, Math.round(value)));
        root.volumePercent = percent;
        if (!setVolumeProcess.running)
            setVolumeProcess.running = true;
    }

    onTrackAvailableChanged: {
        if (!root.trackAvailable)
            root.closePanel();
    }

    Process {
        id: previousFallback
        command: ["spotifast", "previous"]
        running: false
    }

    Process {
        id: playPauseFallback
        command: ["spotifast", "play-pause"]
        running: false
    }

    Process {
        id: nextFallback
        command: ["spotifast", "next"]
        running: false
    }

    // Read the documented raw status only when the popup opens. No polling loop is used.
    Process {
        id: readNowPlaying
        command: ["spotifast", "now-playing", "--raw"]
        running: false
        stdout: StdioCollector {
            id: nowPlayingOutput
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0)
                root.parseVolume(nowPlayingOutput.text);
        }
    }

    Process {
        id: setVolumeProcess
        command: ["spotifast", "volume", String(root.volumePercent)]
        running: false
    }

    Item {
        id: barContent
        anchors.centerIn: parent
        width: Math.min(parent.width, 190)
        height: parent.height
        opacity: barMouse.containsMouse ? 1 : 0.94

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Row {
            id: barContentRow
            anchors.fill: parent
            spacing: 7

            Item {
                id: equalizer
                width: 11
                height: 14
                anchors.verticalCenter: parent.verticalCenter

                Item {
                    id: equalizerBars
                    anchors.fill: parent

                    Rectangle {
                        id: equalizerBar1
                        property real heightLevel: 4
                        anchors.bottom: parent.bottom
                        x: 0
                        width: 2
                        height: root.isPlaying ? heightLevel : 3
                        color: root.foregroundColor

                        SequentialAnimation {
                            running: root.isPlaying
                            loops: Animation.Infinite
                            NumberAnimation { target: equalizerBar1; property: "heightLevel"; to: 11; duration: 260; easing.type: Easing.InOutSine }
                            NumberAnimation { target: equalizerBar1; property: "heightLevel"; to: 4; duration: 330; easing.type: Easing.InOutSine }
                        }
                    }

                    Rectangle {
                        id: equalizerBar2
                        property real heightLevel: 7
                        anchors.bottom: parent.bottom
                        x: 4
                        width: 2
                        height: root.isPlaying ? heightLevel : 3
                        color: root.foregroundColor

                        SequentialAnimation {
                            running: root.isPlaying
                            loops: Animation.Infinite
                            NumberAnimation { target: equalizerBar2; property: "heightLevel"; to: 12; duration: 340; easing.type: Easing.InOutSine }
                            NumberAnimation { target: equalizerBar2; property: "heightLevel"; to: 3; duration: 250; easing.type: Easing.InOutSine }
                        }
                    }

                    Rectangle {
                        id: equalizerBar3
                        property real heightLevel: 5
                        anchors.bottom: parent.bottom
                        x: 8
                        width: 2
                        height: root.isPlaying ? heightLevel : 3
                        color: root.foregroundColor

                        SequentialAnimation {
                            running: root.isPlaying
                            loops: Animation.Infinite
                            NumberAnimation { target: equalizerBar3; property: "heightLevel"; to: 9; duration: 220; easing.type: Easing.InOutSine }
                            NumberAnimation { target: equalizerBar3; property: "heightLevel"; to: 4; duration: 310; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            Column {
                id: musicMetadata
                width: Math.max(0, barContentRow.width - equalizer.width - barContentRow.spacing)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    id: musicTitleLabel
                    width: parent.width
                    height: 13
                    text: root.spotifastPlayer ? root.spotifastPlayer.trackTitle : ""
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.bold: false
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    id: musicArtistLabel
                    width: parent.width
                    height: 11
                    text: root.spotifastPlayer ? root.spotifastPlayer.trackArtist : ""
                    color: root.foregroundColor
                    opacity: 0.72
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.bold: false
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: root.togglePanel()
        }
    }

    PopupWindow {
        id: playerPanel
        width: root.panelWidth
        height: 244
        color: "transparent"
        visible: false
        grabFocus: true

        anchor.window: root.anchorWindow
        anchor.rect.x: root.panelLeft
        anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + 8 : 36

        onVisibleChanged: {
            if (visible)
                root.refreshVolume();
        }

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            enabled: playerPanel.visible
            onActivated: root.closePanel()
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            border.width: 1
            border.color: "#ffffff"
            radius: 0

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 0

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰝚  MUSIC"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 14
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.spotifastPlayer && root.spotifastPlayer.isPlaying ? "PLAYING" : "PAUSED"
                        color: root.foregroundColor
                        opacity: 0.7
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#303030"
                }

                Row {
                    width: parent.width
                    height: 104
                    spacing: 12

                    Rectangle {
                        id: artworkFrame
                        width: 88
                        height: 88
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#111111"
                        border.width: 1
                        border.color: "#303030"

                        Image {
                            id: artworkImage
                            anchors.fill: parent
                            source: root.spotifastPlayer ? root.spotifastPlayer.trackArtUrl : ""
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰎆"
                            color: root.foregroundColor
                            opacity: 0.55
                            font.family: root.fontFamily
                            font.pixelSize: 28
                            visible: artworkImage.status !== Image.Ready
                        }
                    }

                    Column {
                        width: parent.width - artworkFrame.width - parent.spacing
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Item { width: 1; height: 5 }

                        Text {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackTitle : ""
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }

                        Text {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackArtist : ""
                            color: root.foregroundColor
                            opacity: 0.74
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackAlbum : ""
                            color: root.foregroundColor
                            opacity: 0.5
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#303030"
                }

                Item {
                    width: parent.width
                    height: 38

                    Row {
                        anchors.centerIn: parent
                        height: parent.height
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 27
                            anchors.verticalCenter: parent.verticalCenter
                            color: previousMouse.containsMouse ? "#1c1c1c" : "#080808"
                            border.width: 1
                            border.color: "#373737"

                            Text {
                                anchors.centerIn: parent
                                text: "󰒮"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 15
                            }

                            MouseArea {
                                id: previousMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runPrevious()
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 29
                            anchors.verticalCenter: parent.verticalCenter
                            color: playPauseMouse.containsMouse ? "#1c1c1c" : "#080808"
                            border.width: 1
                            border.color: "#ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: root.spotifastPlayer && root.spotifastPlayer.isPlaying ? "󰏤" : "󰐊"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 16
                            }

                            MouseArea {
                                id: playPauseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runPlayPause()
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 27
                            anchors.verticalCenter: parent.verticalCenter
                            color: nextMouse.containsMouse ? "#1c1c1c" : "#080808"
                            border.width: 1
                            border.color: "#373737"

                            Text {
                                anchors.centerIn: parent
                                text: "󰒭"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 15
                            }

                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runNext()
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#303030"
                }

                Row {
                    width: parent.width
                    height: 35
                    spacing: 9

                    Text {
                        width: 43
                        height: parent.height
                        text: "󰕾 VOL"
                        color: root.foregroundColor
                        opacity: 0.85
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }

                    Slider {
                        id: volumeSlider
                        width: parent.width - 43 - 42 - 18
                        height: parent.height
                        from: 0
                        to: 100
                        stepSize: 1
                        value: root.volumePercent
                        onMoved: root.volumePercent = Math.round(value)
                        onPressedChanged: {
                            if (!pressed)
                                root.applyVolume(value);
                        }

                        background: Rectangle {
                            x: volumeSlider.leftPadding
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            width: volumeSlider.availableWidth
                            height: 3
                            color: "#303030"
                            Rectangle {
                                width: volumeSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#ffffff"
                            }
                        }

                        handle: Rectangle {
                            x: volumeSlider.leftPadding
                                + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            width: 6
                            height: 12
                            radius: 0
                            color: "#ffffff"
                            border.width: 1
                            border.color: "#ffffff"
                        }
                    }

                    Text {
                        width: 38
                        height: parent.height
                        text: root.volumePercent + "%"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }


            }
        }
    }
}
