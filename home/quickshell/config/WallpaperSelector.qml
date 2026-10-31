import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

Item {
    id: root

    signal wallpaperApplied(string path)

    readonly property string homeDirectory: String(Quickshell.env("HOME") || "")
    readonly property string wallpaperDirectory: root.homeDirectory + "/Pictures/Wallpapers"

    property string filterText: ""
    property int selectedIndex: 0
    property var wallpapers: []
    property bool isLoading: true
    property bool isApplying: false
    property string pendingPath: ""
    property int pendingIndex: 0
    property int pendingTotal: 0
    property string statusMessage: ""

    readonly property var filteredWallpapers: {
        const query = root.filterText.trim().toLowerCase();
        if (query.length === 0)
            return root.wallpapers;

        return root.wallpapers.filter(function(item) {
            return item.name.toLowerCase().includes(query)
                || item.path.toLowerCase().includes(query);
        });
    }

    readonly property int columns: Math.max(1, Math.floor(wallpaperGrid.width / wallpaperGrid.cellWidth))

    readonly property var selectedWallpaper: root.selectedIndex >= 0
        && root.selectedIndex < root.filteredWallpapers.length
        ? root.filteredWallpapers[root.selectedIndex]
        : null

    readonly property var scanCommand: [
        "bash", "-c",
        'directory="$1"\n' +
        '[ -d "$directory" ] || exit 2\n' +
        'find "$directory" -maxdepth 1 -type f \\( ' +
        '-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o ' +
        '-iname "*.webp" \\) -print0 2>/dev/null | sort -z',
        "WallpaperSelector",
        root.wallpaperDirectory
    ]

    readonly property var applyCommand: [
        "bash", "-c",
        'path="$1"\n' +
        'index="$2"\n' +
        'total="$3"\n' +
        'if ! command -v awww >/dev/null 2>&1; then\n' +
        '  printf "%s\\n" "awww is not installed or is not in PATH" >&2\n' +
        '  exit 127\n' +
        'fi\n' +
        'if ! awww query >/dev/null 2>&1; then\n' +
        '  runtime_dir="${XDG_RUNTIME_DIR:-/tmp/awww}"\n' +
        '  socket_found=0\n' +
        '  for socket_path in "$runtime_dir/${WAYLAND_DISPLAY}-awww-daemon"*; do\n' +
        '    if [ -S "$socket_path" ]; then\n' +
        '      socket_found=1\n' +
        '      break\n' +
        '    fi\n' +
        '  done\n' +
        '  if [ "$socket_found" -eq 1 ]; then\n' +
        '    printf "%s\\n" "awww socket exists but does not answer; refusing to start a duplicate daemon" >&2\n' +
        '    exit 1\n' +
        '  fi\n' +
        '  if ! command -v awww-daemon >/dev/null 2>&1; then\n' +
        '    printf "%s\\n" "awww-daemon was not found in PATH" >&2\n' +
        '    exit 127\n' +
        '  fi\n' +
        '  awww-daemon --quiet >/dev/null 2>&1 &\n' +
        '  daemon_pid=$!\n' +
        '  daemon_ready=0\n' +
        '  for attempt in $(seq 1 30); do\n' +
        '    if awww query >/dev/null 2>&1; then\n' +
        '      daemon_ready=1\n' +
        '      break\n' +
        '    fi\n' +
        '    if ! kill -0 "$daemon_pid" 2>/dev/null; then\n' +
        '      break\n' +
        '    fi\n' +
        '    sleep 0.2\n' +
        '  done\n' +
        '  if [ "$daemon_ready" -ne 1 ]; then\n' +
        '    printf "%s\\n" "awww-daemon did not become ready; check for a stale or occupied socket" >&2\n' +
        '    exit 1\n' +
        '  fi\n' +
        'fi\n' +
        'name=$(basename -- "$path")\n' +
        'transition_pos="$(shuf -i 0-3439 -n 1),$(shuf -i 0-1439 -n 1)"\n' +
        'if ! awww img "$path" --transition-type grow --transition-fps 144 --transition-pos "$transition_pos"; then\n' +
        '  printf "%s\\n" "awww could not apply the wallpaper" >&2\n' +
        '  exit 1\n' +
        'fi\n' +
        'if command -v notify-send >/dev/null 2>&1; then\n' +
        '  notify-send "⏺ wallpaper" "$name ($index/$total)" || true\n' +
        'fi',
        "WallpaperApply",
        root.pendingPath,
        String(root.pendingIndex),
        String(root.pendingTotal)
    ]

    function fileName(path) {
        const parts = String(path || "").split("/");
        return parts.length > 0 ? parts[parts.length - 1] : String(path || "");
    }

    function fileUrl(path) {
        return "file://" + encodeURI(String(path || ""))
            .replace(/#/g, "%23")
            .replace(/\?/g, "%3F");
    }

    function parseWallpaperList(output) {
        const paths = String(output || "").split("\u0000");
        const items = [];
        for (let i = 0; i < paths.length; i++) {
            const path = paths[i];
            if (!path || path.length === 0)
                continue;
            items.push({
                path: path,
                name: root.fileName(path),
                id: path
            });
        }
        root.wallpapers = items;
        root.selectedIndex = 0;
    }

    function moveSelection(offset) {
        const count = root.filteredWallpapers.length;
        if (count === 0)
            return;

        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + offset));
        wallpaperGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    function applySelected() {
        if (!root.selectedWallpaper || root.isApplying)
            return;

        root.pendingPath = root.selectedWallpaper.path;
        const fullIndex = root.wallpapers.findIndex(function(item) {
            return item.path === root.pendingPath;
        });
        root.pendingIndex = fullIndex >= 0 ? fullIndex + 1 : root.selectedIndex + 1;
        root.pendingTotal = root.wallpapers.length;
        root.statusMessage = "Applying wallpaper…";
        root.isApplying = true;
        applyProcess.running = true;
    }

    function refreshWallpapers() {
        if (scanProcess.running)
            return;
        root.isLoading = true;
        root.statusMessage = "Scanning wallpapers…";
        scanProcess.running = true;
    }

    onFilterTextChanged: {
        root.selectedIndex = 0;
        root.statusMessage = "";
    }

    onFilteredWallpapersChanged: {
        if (root.filteredWallpapers.length === 0)
            root.selectedIndex = 0;
        else
            root.selectedIndex = Math.min(root.selectedIndex, root.filteredWallpapers.length - 1);
    }

    Component.onCompleted: root.refreshWallpapers()

    Process {
        id: scanProcess
        command: root.scanCommand

        stdout: StdioCollector {
            onStreamFinished: root.parseWallpaperList(this.text)
        }

        onExited: function(exitCode, exitStatus) {
            root.isLoading = false;
            if (exitCode !== 0 && root.wallpapers.length === 0)
                root.statusMessage = "Wallpaper folder not found or unavailable.";
            else if (root.wallpapers.length === 0)
                root.statusMessage = "No supported images in ~/Pictures/Wallpapers.";
            else
                root.statusMessage = "";
        }
    }

    Process {
        id: applyProcess
        command: root.applyCommand

        stdout: StdioCollector {
            id: applyOutput
        }

        stderr: StdioCollector {
            id: applyErrors
        }

        onExited: function(exitCode, exitStatus) {
            root.isApplying = false;
            if (exitCode === 0) {
                root.statusMessage = "Wallpaper applied";
                Theme.syncWallpaper();
                root.wallpaperApplied(root.pendingPath);
            } else {
                const details = String(applyErrors.text || applyOutput.text || "").trim();
                root.statusMessage = details.length > 0
                    ? details.split(/\r?\n/)[0]
                    : "Could not apply wallpaper. Check the wallpaper service.";
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10

        Item {
            id: header
            width: parent.width
            height: 32

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    width: 32
                    height: 32
                    radius: 11
                    color: Theme.tint(Theme.iris, 0.18)

                    Icon {
                        anchors.centerIn: parent
                        text: Theme.icons.image
                        color: Theme.iris
                    }
                }

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpapers"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.isLoading
                        ? "Scanning…"
                        : root.filteredWallpapers.length + " of " + root.wallpapers.length
                    color: Theme.subtle
                    font.pixelSize: 11
                }
            }

            SoftButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Refresh"
                glyph: Theme.icons.refresh
                fontSize: 11
                enabled: !root.isLoading
                onClicked: root.refreshWallpapers()
            }

            Row {
                anchors.right: refreshButton.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpaper + GTK colors"
                    color: Theme.subtle
                    font.pixelSize: 11
                }

                SoftSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Theme.wallpaperColors
                    enabled: !Theme.switchingColors
                    onClicked: Theme.setWallpaperColors(!Theme.wallpaperColors)
                }
            }
        }

        Row {
            id: body
            width: parent.width
            height: Math.max(0, parent.height - header.height - footer.height - 20)
            spacing: 16

            Item {
                id: gridPane
                width: Math.floor((body.width - body.spacing) * 0.62)
                height: body.height

                GridView {
                    id: wallpaperGrid
                    anchors.fill: parent
                    clip: true
                    cellWidth: 194
                    cellHeight: 126
                    model: root.filteredWallpapers
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: false

                    delegate: Item {
                        id: wallpaperTile
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: index === root.selectedIndex

                        width: wallpaperGrid.cellWidth - 10
                        height: wallpaperGrid.cellHeight - 10

                        // Gradient ring around the selected tile.
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusTile + 3
                            gradient: Theme.dusk
                            opacity: wallpaperTile.isSelected ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.fast }
                            }
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: Theme.radiusTile
                            color: Theme.surface

                            Image {
                                id: thumbnail
                                anchors.fill: parent
                                source: root.fileUrl(wallpaperTile.modelData.path)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: thumbnail.status !== Image.Ready
                                text: Theme.icons.image
                                color: Theme.muted
                                font.pixelSize: 22
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 34
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Theme.tint(Theme.base, 0) }
                                    GradientStop { position: 1.0; color: Theme.tint(Theme.base, 0.92) }
                                }
                            }

                            UiText {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.bottomMargin: 6
                                text: wallpaperTile.modelData.name
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideMiddle
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = wallpaperTile.index
                            onClicked: root.selectedIndex = wallpaperTile.index
                            onDoubleClicked: {
                                root.selectedIndex = wallpaperTile.index;
                                root.applySelected();
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 30
                    spacing: 6
                    visible: root.filteredWallpapers.length === 0

                    UiText {
                        width: parent.width
                        text: root.isLoading ? "Scanning wallpapers" : "No wallpapers found"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    UiText {
                        width: parent.width
                        text: root.isLoading
                            ? "Reading ~/Pictures/Wallpapers"
                            : (root.filterText.trim().length > 0
                                ? "Try another search term."
                                : "Add images to ~/Pictures/Wallpapers and refresh.")
                        color: Theme.subtle
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                id: previewPane
                width: Math.max(0, body.width - gridPane.width - body.spacing)
                height: body.height
                radius: 20
                color: Theme.surface

                ClippingRectangle {
                    id: previewFrame
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    height: Math.min(parent.height * 0.62, width * 0.72)
                    radius: 14
                    color: Theme.base

                    Image {
                        id: largePreview
                        anchors.fill: parent
                        source: root.selectedWallpaper
                            ? root.fileUrl(root.selectedWallpaper.path)
                            : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                    }

                    UiText {
                        anchors.centerIn: parent
                        text: root.selectedWallpaper ? "Loading preview" : "Select a wallpaper"
                        color: Theme.subtle
                        font.pixelSize: 12
                        visible: !root.selectedWallpaper || largePreview.status !== Image.Ready
                    }
                }

                UiText {
                    id: selectedName
                    anchors.top: previewFrame.bottom
                    anchors.topMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    text: root.selectedWallpaper ? root.selectedWallpaper.name : "No wallpaper selected"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    elide: Text.ElideMiddle
                }

                UiText {
                    id: selectedPath
                    anchors.top: selectedName.bottom
                    anchors.topMargin: 3
                    anchors.left: selectedName.left
                    anchors.right: selectedName.right
                    text: root.selectedWallpaper ? root.selectedWallpaper.path : root.wallpaperDirectory
                    color: Theme.subtle
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }

                SoftButton {
                    id: applyButton
                    anchors.top: selectedPath.bottom
                    anchors.topMargin: 14
                    anchors.left: selectedName.left
                    anchors.right: selectedName.right
                    implicitHeight: 40
                    label: root.isApplying ? "Applying…" : "Apply wallpaper"
                    variant: "accent"
                    accent: Theme.iris
                    enabled: Boolean(root.selectedWallpaper) && !root.isApplying
                    onClicked: root.applySelected()
                }

                UiText {
                    anchors.top: applyButton.bottom
                    anchors.topMargin: 8
                    anchors.left: selectedName.left
                    anchors.right: selectedName.right
                    text: root.statusMessage
                    color: root.statusMessage === "Wallpaper applied" ? Theme.mint : Theme.subtle
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: footer
            width: parent.width
            height: 16

            UiText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "↑ ↓ ← → move  ·  Enter or double click to apply"
                color: Theme.muted
                font.pixelSize: 10
            }

            UiText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Esc closes"
                color: Theme.muted
                font.pixelSize: 10
            }
        }
    }
}
