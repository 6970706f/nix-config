import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

Item {
    id: root

    signal wallpaperApplied(string path)

    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"
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
        root.statusMessage = "APPLYING WALLPAPER…";
        root.isApplying = true;
        applyProcess.running = true;
    }

    function refreshWallpapers() {
        if (scanProcess.running)
            return;
        root.isLoading = true;
        root.statusMessage = "SCANNING WALLPAPERS…";
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
                root.statusMessage = "WALLPAPER APPLIED";
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
            height: 27

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "WALLPAPER LIBRARY"
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 1.0
            }

            Rectangle {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 68
                height: 22
                color: refreshMouse.containsMouse ? "#171717" : "#080808"
                border.width: 1
                border.color: "#454545"

                Text {
                    anchors.centerIn: parent
                    text: "↻ REFRESH"
                    color: root.isLoading ? "#666666" : "#b8b8b8"
                    font.family: root.fontFamily
                    font.pixelSize: 9
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    enabled: !root.isLoading
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.refreshWallpapers()
                }
            }

            Text {
                anchors.right: refreshButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.isLoading
                    ? "SCANNING…"
                    : root.filteredWallpapers.length + " / " + root.wallpapers.length + " IMAGES"
                color: "#b8b8b8"
                font.family: root.fontFamily
                font.pixelSize: 10
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "#333333"
        }

        Row {
            id: body
            width: parent.width
            height: Math.max(0, parent.height - header.height - footer.height - 31)
            spacing: 14

            Item {
                id: gridPane
                width: Math.floor((body.width - body.spacing - 1) * 0.62)
                height: body.height

                Text {
                    id: gridTitle
                    anchors.top: parent.top
                    anchors.left: parent.left
                    text: root.filterText.trim().length > 0
                        ? "MATCHING WALLPAPERS"
                        : "AVAILABLE WALLPAPERS"
                    color: "#b8b8b8"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 0.6
                }

                GridView {
                    id: wallpaperGrid
                    anchors.top: gridTitle.bottom
                    anchors.topMargin: 9
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    clip: true
                    cellWidth: 194
                    cellHeight: 136
                    model: root.filteredWallpapers
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: false

                    delegate: Item {
                        id: wallpaperTile
                        required property var modelData
                        required property int index

                        width: wallpaperGrid.cellWidth - 10
                        height: wallpaperGrid.cellHeight - 10

                        Rectangle {
                            anchors.fill: parent
                            color: index === root.selectedIndex ? "#171717" : "#080808"
                            border.width: 1
                            border.color: index === root.selectedIndex ? "#ffffff" : "#343434"
                        }

                        Rectangle {
                            width: 2
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: "#ffffff"
                            visible: index === root.selectedIndex
                        }

                        Image {
                            id: thumbnail
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            height: 83
                            source: root.fileUrl(wallpaperTile.modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true

                            Rectangle {
                                anchors.fill: parent
                                color: "#101010"
                                visible: thumbnail.status !== Image.Ready

                                Text {
                                    anchors.centerIn: parent
                                    text: thumbnail.status === Image.Loading ? "LOADING" : "IMAGE"
                                    color: "#777777"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 7
                            text: wallpaperTile.modelData.name
                            color: index === root.selectedIndex ? "#ffffff" : "#b8b8b8"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
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
                    spacing: 8
                    visible: root.filteredWallpapers.length === 0

                    Text {
                        width: parent.width
                        text: root.isLoading ? "SCANNING WALLPAPERS" : "NO WALLPAPERS FOUND"
                        color: "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        width: parent.width
                        text: root.isLoading
                            ? "Reading ~/Pictures/Wallpapers"
                            : (root.filterText.trim().length > 0
                                ? "Try another search term."
                                : "Add images to ~/Pictures/Wallpapers and refresh.")
                        color: "#888888"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                width: 1
                height: body.height
                color: "#333333"
            }

            Item {
                id: previewPane
                width: Math.max(0, body.width - gridPane.width - body.spacing - 1 - body.spacing)
                height: body.height

                Text {
                    id: previewTitle
                    anchors.top: parent.top
                    anchors.left: parent.left
                    text: "PREVIEW"
                    color: "#b8b8b8"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 0.6
                }

                Rectangle {
                    id: previewFrame
                    anchors.top: previewTitle.bottom
                    anchors.topMargin: 9
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.min(parent.height * 0.70, width * 0.82)
                    color: "#050505"
                    border.width: 1
                    border.color: "#444444"
                    clip: true

                    Image {
                        id: largePreview
                        anchors.fill: parent
                        anchors.margins: 1
                        source: root.selectedWallpaper
                            ? root.fileUrl(root.selectedWallpaper.path)
                            : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.selectedWallpaper ? "LOADING PREVIEW" : "SELECT A WALLPAPER"
                        color: "#777777"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        visible: !root.selectedWallpaper || largePreview.status !== Image.Ready
                    }
                }

                Text {
                    id: selectedName
                    anchors.top: previewFrame.bottom
                    anchors.topMargin: 13
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.selectedWallpaper ? root.selectedWallpaper.name : "No wallpaper selected"
                    color: "#ffffff"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }

                Text {
                    id: selectedPath
                    anchors.top: selectedName.bottom
                    anchors.topMargin: 5
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.selectedWallpaper ? root.selectedWallpaper.path : root.wallpaperDirectory
                    color: "#777777"
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    id: applyButton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: selectedPath.bottom
                    anchors.topMargin: 16
                    height: 39
                    color: root.selectedWallpaper && !root.isApplying ? "#ffffff" : "#171717"
                    border.width: 1
                    border.color: root.selectedWallpaper && !root.isApplying ? "#ffffff" : "#454545"
                    opacity: root.selectedWallpaper && !root.isApplying ? 1.0 : 0.65

                    Text {
                        anchors.centerIn: parent
                        text: root.isApplying ? "APPLYING…" : "APPLY WALLPAPER  ↵"
                        color: root.selectedWallpaper && !root.isApplying ? "#000000" : "#888888"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: Boolean(root.selectedWallpaper) && !root.isApplying
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.applySelected()
                    }
                }

                Text {
                    anchors.top: applyButton.bottom
                    anchors.topMargin: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.statusMessage
                    color: root.statusMessage === "WALLPAPER APPLIED" ? "#ffffff" : "#999999"
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: footer
            width: parent.width
            height: 17

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "↑ ↓ MOVE  ·  ← → SELECT  ·  ENTER APPLY  ·  DOUBLE CLICK TO APPLY"
                color: "#777777"
                font.family: root.fontFamily
                font.pixelSize: 9
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "ESC CLOSE"
                color: "#777777"
                font.family: root.fontFamily
                font.pixelSize: 9
            }
        }
    }
}
