import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: root

    // Window anchoring is supplied by the existing bar.
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

    height: Theme.tabHeight
    visible: width >= 130

    readonly property int panelWidth: 376 + Theme.popupPadX * 2
    readonly property int panelLeft: {
        if (!root.anchorWindow)
            return 0;

        // Re-read the anchor on open: bar tabs shift as their content changes.
        playerPanel.visible;
        const point = barContent.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const maximumX = Math.max(0, root.anchorWindow.width - root.panelWidth);
        return Math.max(0, Math.min(
            point.x + barContent.width / 2 - root.panelWidth / 2,
            maximumX
        ));
    }

    function openPanel() {
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

    function openApp() {
        Quickshell.execDetached({
            command: root.spotifastPlayer ? ["spotifast", "show"] : ["spotifast"]
        });
        root.closePanel();
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

    // Leave the idle disc upright instead of wherever the last track stopped it.
    onTrackAvailableChanged: {
        if (!root.trackAvailable)
            barCover.rotation = 0;
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
        anchors.left: parent.left
        width: Math.min(parent.width, barTab.width)
        height: parent.height

        BarTab {
            id: barTab
            width: Math.min(barContent.parent.width, implicitWidth)
            sidePadding: 4
            spacing: 8

            // The cover turns like a record while the track plays.
            ClippingRectangle {
                id: barCover
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: Theme.raised

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 9000
                    loops: Animation.Infinite
                    running: root.trackAvailable
                    paused: running && !root.isPlaying
                }

                Image {
                    id: barCoverImage
                    anchors.fill: parent
                    source: root.spotifastPlayer ? root.spotifastPlayer.trackArtUrl : ""
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 64
                    sourceSize.height: 64
                    smooth: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: barCoverImage.status !== Image.Ready
                    text: Theme.icons.musicNote
                    color: Theme.iris
                    font.pixelSize: 14
                }
            }

            Column {
                id: musicMetadata
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(150, Math.max(musicTitleLabel.implicitWidth, musicArtistLabel.implicitWidth))
                spacing: -1

                UiText {
                    id: musicTitleLabel
                    width: parent.width
                    text: root.trackAvailable ? root.spotifastPlayer.trackTitle : "Spotifast"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                UiText {
                    id: musicArtistLabel
                    width: parent.width
                    text: root.trackAvailable
                        ? root.spotifastPlayer.trackArtist
                        : (root.spotifastPlayer ? "Nothing playing" : "Closed")
                    color: Theme.subtle
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
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
        height: 268 + Theme.popupPadY
        color: "transparent"
        visible: false
        grabFocus: true

        anchor.window: root.anchorWindow
        anchor.rect.x: root.panelLeft
        anchor.rect.y: root.anchorWindow ? root.anchorWindow.height : 36

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

        Shortcut {
            sequence: "Space"
            context: Qt.WindowShortcut
            enabled: playerPanel.visible && root.trackAvailable
            autoRepeat: false
            onActivated: root.runPlayPause()
        }

        Shortcut {
            sequence: "Right"
            context: Qt.WindowShortcut
            enabled: playerPanel.visible && root.trackAvailable
            autoRepeat: false
            onActivated: root.runNext()
        }

        Shortcut {
            sequence: "Left"
            context: Qt.WindowShortcut
            enabled: playerPanel.visible && root.trackAvailable
            autoRepeat: false
            onActivated: root.runPrevious()
        }

        Shortcut {
            sequences: ["Return", "Enter"]
            context: Qt.WindowShortcut
            enabled: playerPanel.visible && !root.trackAvailable
            autoRepeat: false
            onActivated: root.openApp()
        }

        PanelSurface {
            id: playerSurface
            window: playerPanel
            accent: Theme.iris
            padding: 0

            // The cover, blurred and darkened, tints the whole card.
            ClippingRectangle {
                anchors.fill: parent
                radius: Theme.radiusCard
                color: "transparent"

                Image {
                    id: backdropSource
                    anchors.fill: parent
                    visible: false
                    source: artworkImage.source
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 128
                    sourceSize.height: 128
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: backdropSource.status === Image.Ready
                    source: backdropSource
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 48
                    blur: 1
                    saturation: -1
                    brightness: -0.1
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.tint(Theme.base, 0.45) }
                        GradientStop { position: 0.75; color: Theme.tint(Theme.base, 0.92) }
                    }
                }
            }

            // Shown instead of the controls while there is no track to control.
            Column {
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 6
                visible: !root.trackAvailable

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 84
                    radius: 42
                    color: Theme.raised
                    border.width: 1
                    border.color: Theme.stroke

                    Icon {
                        anchors.centerIn: parent
                        text: Theme.icons.musicNote
                        color: Theme.muted
                        font.pixelSize: 36
                    }
                }

                Item {
                    width: 1
                    height: 4
                }

                UiText {
                    width: parent.width
                    text: root.spotifastPlayer ? "Nothing playing" : "Spotifast is closed"
                    font.family: Theme.displayFont
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: parent.width
                    text: root.spotifastPlayer ? "Pick something to listen to" : "Open it to start listening"
                    color: Theme.subtle
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    width: 1
                    height: 6
                }

                SoftButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitHeight: 36
                    variant: "accent"
                    accent: Theme.iris
                    glyph: Theme.icons.music
                    label: "Open Spotifast"
                    onClicked: root.openApp()
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                visible: root.trackAvailable

                Row {
                    width: parent.width
                    height: 112
                    spacing: 14

                    Item {
                        id: artworkFrame
                        width: 112
                        height: 112

                        // Rings ripple out from the disc while the track plays.
                        Repeater {
                            model: 2

                            delegate: Rectangle {
                                id: pulseRing
                                required property int index
                                readonly property int delay: index * 900

                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: 1.5
                                border.color: Theme.iris
                                opacity: 0
                                visible: root.isPlaying

                                SequentialAnimation {
                                    running: root.isPlaying && playerPanel.visible
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: pulseRing.delay }
                                    ParallelAnimation {
                                        NumberAnimation { target: pulseRing; property: "scale"; from: 1; to: 1.22; duration: 2000; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: pulseRing; property: "opacity"; from: 0.5; to: 0; duration: 2000; easing.type: Easing.OutCubic }
                                    }
                                    PauseAnimation { duration: 900 - pulseRing.delay }
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            scale: root.isPlaying ? 1 : 0.94

                            Behavior on scale {
                                NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic }
                            }

                            RectangularShadow {
                                anchors.fill: parent
                                radius: width / 2
                                blur: 18
                                offset.y: 6
                                color: Qt.rgba(0, 0, 0, 0.5)
                            }

                            // Same disc as the bar, turning in step with it.
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.raised
                                rotation: barCover.rotation

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

                                Icon {
                                    anchors.centerIn: parent
                                    text: Theme.icons.musicNote
                                    color: Theme.iris
                                    font.pixelSize: 36
                                    visible: artworkImage.status !== Image.Ready
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width - artworkFrame.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Row {
                            spacing: 8

                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.isPlaying ? "Now playing" : "Paused"
                                color: Theme.iris
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }

                            Item {
                                id: equalizer
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14

                                Repeater {
                                    model: [
                                        { x: 0, rest: 4, peak: 11, up: 260, down: 330 },
                                        { x: 5, rest: 6, peak: 14, up: 340, down: 250 },
                                        { x: 10, rest: 5, peak: 10, up: 220, down: 310 }
                                    ]

                                    delegate: Rectangle {
                                        id: equalizerBar
                                        required property var modelData
                                        property real heightLevel: modelData.rest

                                        anchors.bottom: parent.bottom
                                        x: modelData.x
                                        width: 3
                                        radius: 1.5
                                        height: root.isPlaying ? heightLevel : 3
                                        color: Theme.iris

                                        SequentialAnimation {
                                            running: root.isPlaying && playerPanel.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { target: equalizerBar; property: "heightLevel"; to: equalizerBar.modelData.peak; duration: equalizerBar.modelData.up; easing.type: Easing.InOutSine }
                                            NumberAnimation { target: equalizerBar; property: "heightLevel"; to: equalizerBar.modelData.rest; duration: equalizerBar.modelData.down; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                            }
                        }

                        UiText {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackTitle : ""
                            font.family: Theme.displayFont
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }

                        UiText {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackArtist : ""
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        UiText {
                            width: parent.width
                            text: root.spotifastPlayer ? root.spotifastPlayer.trackAlbum : ""
                            color: Theme.subtle
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 54
                    spacing: 16

                    SoftButton {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 40
                        variant: "ghost"
                        glyph: Theme.icons.previous
                        fontSize: 18
                        onClicked: root.runPrevious()
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        height: 54
                        radius: 27
                        gradient: Theme.dusk
                        scale: playPauseMouse.pressed ? 0.92 : (playPauseMouse.containsMouse ? 1.05 : 1)

                        Behavior on scale {
                            NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack }
                        }

                        Icon {
                            anchors.centerIn: parent
                            text: root.spotifastPlayer && root.spotifastPlayer.isPlaying
                                ? Theme.icons.pause
                                : Theme.icons.play
                            color: Theme.onAccent
                            font.pixelSize: 26
                        }

                        MouseArea {
                            id: playPauseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runPlayPause()
                        }
                    }

                    SoftButton {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 40
                        variant: "ghost"
                        glyph: Theme.icons.next
                        fontSize: 18
                        onClicked: root.runNext()
                    }
                }

                Row {
                    width: parent.width
                    height: 26
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icons.volumeHigh
                        color: Theme.iris
                    }

                    SoftSlider {
                        id: volumeSlider
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16 - 38 - parent.spacing * 2
                        from: 0
                        to: 100
                        stepSize: 1
                        accent: Theme.iris
                        value: root.volumePercent
                        onMoved: root.volumePercent = Math.round(value)
                        onPressedChanged: {
                            if (!pressed)
                                root.applyVolume(value);
                        }
                    }

                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        text: root.volumePercent + "%"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
