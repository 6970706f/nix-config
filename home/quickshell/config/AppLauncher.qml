import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property int maxWidth: 1080
    readonly property int maxHeight: 780
    readonly property int outerMargin: 12
    readonly property int topGap: 8

    property string searchQuery: ""
    property int selectedIndex: 0
    property string launchError: ""
    property var categoryFilter: []
    property bool applyingQuickSearch: false
    property var launchCounts: ({})

    readonly property var allApplications: {
        return [...DesktopEntries.applications.values]
            .filter(function(entry) {
                return entry && !entry.noDisplay && (entry.name || entry.id);
            })
            .sort(function(first, second) {
                return String(first.name || first.id).localeCompare(
                    String(second.name || second.id)
                );
            });
    }

    readonly property var usageSortedApplications: {
        const counts = root.launchCounts;
        return [...root.allApplications].sort(function(first, second) {
            const firstCount = Number(counts[first.id] || 0);
            const secondCount = Number(counts[second.id] || 0);
            return secondCount - firstCount
                || String(first.name || first.id).localeCompare(String(second.name || second.id));
        });
    }

    readonly property var topApplications: root.usageSortedApplications.slice(0, 6)

    readonly property var quickSearches: [
        { label: "Development", icon: "", categories: ["Development"] },
        { label: "Internet", icon: "", categories: ["Network", "WebBrowser"] },
        { label: "Settings", icon: "", categories: ["Settings", "System"] },
        { label: "Multimedia", icon: "", categories: ["AudioVideo", "Audio", "Video"] },
        { label: "Utilities", icon: "", categories: ["Utility"] },
        { label: "Games", icon: "", categories: ["Game"] }
    ]

    readonly property var filteredApplications: {
        const query = root.searchQuery.trim().toLowerCase();
        const requiredCategories = root.categoryFilter;

        return root.allApplications.filter(function(entry) {
            if (requiredCategories.length > 0) {
                const entryCategories = (entry.categories || []).map(function(category) {
                    return String(category).toLowerCase();
                });
                return requiredCategories.some(function(category) {
                    return entryCategories.indexOf(String(category).toLowerCase()) !== -1;
                });
            }

            if (query.length === 0)
                return true;

            const searchableText = [
                entry.name || "",
                entry.genericName || "",
                entry.comment || "",
                (entry.keywords || []).join(" "),
                (entry.categories || []).join(" "),
                entry.id || ""
            ].join(" ").toLowerCase();

            return searchableText.includes(query);
        });
    }

    width: root.anchorWindow && root.anchorWindow.screen
        ? Math.max(320, Math.min(root.maxWidth, root.anchorWindow.screen.width - 24))
        : root.maxWidth
    height: root.anchorWindow && root.anchorWindow.screen
        ? Math.max(320, Math.min(
            root.maxHeight,
            root.anchorWindow.screen.height - root.anchorWindow.height - root.topGap - root.outerMargin
        ))
        : root.maxHeight

    color: "transparent"
    visible: false

    // Use a native popup like the other modules. Its focus grab dismisses it
    // on outside click without creating a full-screen input surface.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.outerMargin
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + root.topGap : 34
    grabFocus: true

    function openPanel() {
        if (root.visible) {
            Qt.callLater(function() { searchInput.forceActiveFocus(); });
            return;
        }

        root.launchError = "";
        root.selectedIndex = 0;
        root.categoryFilter = [];
        root.applyingQuickSearch = false;
        searchInput.text = "";
        root.searchQuery = "";
        root.visible = true;

        Qt.callLater(function() {
            if (!root.visible)
                return;
            searchInput.forceActiveFocus();
            searchInput.cursorPosition = searchInput.text.length;
        });
    }

    function closePanel() {
        if (!root.visible)
            return;

        root.visible = false;
        searchInput.text = "";
        root.searchQuery = "";
        root.categoryFilter = [];
        root.selectedIndex = 0;
        root.launchError = "";
    }

    function togglePanel() {
        if (root.visible)
            root.closePanel();
        else
            root.openPanel();
    }

    function categoryApplicationCount(searchItem) {
        const requiredCategories = (searchItem.categories || []).map(function(category) {
            return String(category).toLowerCase();
        });

        return root.allApplications.filter(function(entry) {
            const entryCategories = (entry.categories || []).map(function(category) {
                return String(category).toLowerCase();
            });
            return requiredCategories.some(function(category) {
                return entryCategories.indexOf(category) !== -1;
            });
        }).length;
    }

    function applyQuickSearch(searchItem) {
        root.applyingQuickSearch = true;
        root.categoryFilter = searchItem.categories;
        searchInput.text = searchItem.label;
        root.searchQuery = searchItem.label;
        root.selectedIndex = 0;
        root.launchError = "";
        root.applyingQuickSearch = false;
        searchInput.forceActiveFocus();
    }

    function launchApplication(entry) {
        if (!entry) {
            root.launchError = "Select an application first.";
            return;
        }

        const command = entry.command;
        if (!command || command.length === 0) {
            root.launchError = "No launch command is available for this application.";
            console.warn("AppLauncher: no parsed command for", entry.name || entry.id);
            return;
        }

        try {
            // Use the parsed desktop-entry command as an argument list. Do not run Exec through a shell.
            Quickshell.execDetached({
                command: command,
                workingDirectory: entry.workingDirectory
            });

            const updatedCounts = Object.assign({}, root.launchCounts);
            updatedCounts[entry.id] = Number(updatedCounts[entry.id] || 0) + 1;
            root.launchCounts = updatedCounts;

            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: launch failed:", entry.name || entry.id, error);
            root.launchError = "Unable to launch " + (entry.name || "this application") + ". Check qs log.";
        }
    }

    function moveSelection(direction) {
        const count = root.searchQuery.trim().length > 0
            ? root.filteredApplications.length
            : root.allApplications.length;

        if (count === 0) {
            root.selectedIndex = 0;
            return;
        }

        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + direction));

        if (root.searchQuery.trim().length > 0)
            resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else
            allAppsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    onVisibleChanged: {
        if (root.visible) {
            Qt.callLater(function() {
                if (root.visible) {
                    searchInput.forceActiveFocus();
                    searchInput.cursorPosition = searchInput.text.length;
                }
            });
        } else {
            // PopupWindow.grabFocus can hide the window directly on outside
            // click, without calling closePanel(). Keep both close paths equal.
            searchInput.text = "";
            root.searchQuery = "";
            root.categoryFilter = [];
            root.selectedIndex = 0;
            root.launchError = "";
            root.applyingQuickSearch = false;
        }
    }

    onSearchQueryChanged: {
        root.selectedIndex = 0;
        root.launchError = "";
    }

    onFilteredApplicationsChanged: {
        if (root.filteredApplications.length === 0)
            root.selectedIndex = 0;
        else
            root.selectedIndex = Math.min(root.selectedIndex, root.filteredApplications.length - 1);
    }

    ScriptModel {
        id: allApplicationsModel
        objectProp: "id"
        values: root.allApplications
    }

    ScriptModel {
        id: topApplicationsModel
        objectProp: "id"
        values: root.topApplications
    }

    ScriptModel {
        id: filteredApplicationsModel
        objectProp: "id"
        values: root.filteredApplications
    }

    Shortcut {
        id: dismissShortcut
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    Rectangle {
        id: outerSurface
        anchors.fill: parent
        color: root.panelColor
        border.width: 1
        border.color: "#ffffff"
        radius: 0
    }

    Rectangle {
        id: searchBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 42
        color: "#080808"
        border.width: 1
        border.color: "#505050"
        radius: 0

        Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: 15
        }

        TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.foregroundColor
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            font.family: root.fontFamily
            font.pixelSize: 13
            verticalAlignment: TextInput.AlignVCenter
            focus: root.visible
            activeFocusOnTab: true
            selectByMouse: true
            clip: true

            onTextChanged: {
                root.searchQuery = text;
                root.selectedIndex = 0;
                root.launchError = "";
                if (!root.applyingQuickSearch)
                    root.categoryFilter = [];
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.searchQuery.trim().length > 0)
                        root.launchApplication(root.filteredApplications[root.selectedIndex]);
                    else
                        root.launchApplication(root.allApplications[root.selectedIndex]);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    const step = root.searchQuery.trim().length > 0
                        ? 1
                        : (allAppsGrid.width >= 850 ? 5 : (allAppsGrid.width >= 560 ? 3 : 2));
                    root.moveSelection(step);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    const step = root.searchQuery.trim().length > 0
                        ? 1
                        : (allAppsGrid.width >= 850 ? 5 : (allAppsGrid.width >= 560 ? 3 : 2));
                    root.moveSelection(-step);
                    event.accepted = true;
                } else if (root.searchQuery.trim().length === 0 && event.key === Qt.Key_Right) {
                    root.moveSelection(1);
                    event.accepted = true;
                } else if (root.searchQuery.trim().length === 0 && event.key === Qt.Key_Left) {
                    root.moveSelection(-1);
                    event.accepted = true;
                }
            }
        }

        Text {
            z: -1
            anchors.left: searchInput.left
            anchors.right: searchInput.right
            anchors.verticalCenter: searchInput.verticalCenter
            text: "Search applications by name, description or category..."
            color: "#808080"
            font.family: root.fontFamily
            font.pixelSize: 13
            visible: searchInput.text.length === 0
        }

        MouseArea {
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: 10
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 36
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            onClicked: searchInput.forceActiveFocus()
        }
    }

    Item {
        id: mainContent
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        clip: true

        Item {
            id: defaultHome
            anchors.fill: parent
            visible: root.searchQuery.trim().length === 0 && root.launchError.length === 0

            Item {
                id: launcherHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        text: "APP LAUNCHER"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    Text {
                        text: root.allApplications.length + " INSTALLED APPLICATIONS  /  " + root.topApplications.length + " QUICK PICKS"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: mainContent.width > 560

                    Repeater {
                        model: ["↑ ↓  NAVIGATE", "↵  LAUNCH", "ESC  CLOSE"]

                        delegate: Rectangle {
                            required property string modelData
                            width: hintText.implicitWidth + 14
                            height: 22
                            color: "#080808"
                            border.width: 1
                            border.color: "#363636"

                            Text {
                                id: hintText
                                anchors.centerIn: parent
                                text: modelData
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: headerDivider
                anchors.top: launcherHeader.bottom
                anchors.topMargin: 9
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#343434"
            }

            Item {
                id: categoriesHeadingRow
                anchors.top: headerDivider.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CATEGORIES"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FILTER THE LIBRARY"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }

            Item {
                id: quickSearchArea
                anchors.top: categoriesHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                height: quickSearchGrid.columns >= 6 ? 36 : 74

                Grid {
                    id: quickSearchGrid
                    anchors.fill: parent
                    columns: quickSearchArea.width >= 750 ? 6 : (quickSearchArea.width >= 400 ? 3 : 2)
                    spacing: 6

                    Repeater {
                        model: root.quickSearches

                        delegate: Item {
                            id: quickSearchTile
                            required property var modelData
                            required property int index

                            width: Math.floor((quickSearchArea.width - (quickSearchGrid.columns - 1) * quickSearchGrid.spacing) / quickSearchGrid.columns)
                            height: 34

                            Rectangle {
                                anchors.fill: parent
                                color: quickSearchMouse.containsMouse ? "#181818" : "#080808"
                                border.width: 1
                                border.color: quickSearchMouse.containsMouse ? "#666666" : "#363636"
                            }

                            Text {
                                id: quickSearchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: quickSearchTile.modelData.icon
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 12
                            }

                            Text {
                                id: quickSearchLabel
                                anchors.left: quickSearchIcon.right
                                anchors.leftMargin: 7
                                anchors.right: quickSearchCount.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: quickSearchTile.modelData.label
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            Text {
                                id: quickSearchCount
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(root.categoryApplicationCount(quickSearchTile.modelData))
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
                            }

                            MouseArea {
                                id: quickSearchMouse
                                z: 10
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                preventStealing: true
                                onClicked: root.applyQuickSearch(quickSearchTile.modelData)
                            }
                        }
                    }
                }
            }

            Item {
                id: quickLaunchHeadingRow
                anchors.top: quickSearchArea.bottom
                anchors.topMargin: 13
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "QUICK LAUNCH"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MOST USED APPS RISE TO THE TOP"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }

            GridView {
                id: topAppsGrid
                anchors.top: quickLaunchHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                height: cellHeight * Math.ceil(root.topApplications.length / (width >= 750 ? 6 : 3))
                clip: true
                cellWidth: width / (width >= 750 ? 6 : 3)
                cellHeight: 88
                model: topApplicationsModel
                interactive: false
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: topAppTile
                    required property var modelData
                    required property int index

                    width: topAppsGrid.cellWidth - 7
                    height: topAppsGrid.cellHeight - 7

                    Rectangle {
                        anchors.fill: parent
                        color: topAppMouse.containsMouse ? "#171717" : "#070707"
                        border.width: 1
                        border.color: topAppMouse.containsMouse ? "#727272" : "#343434"
                    }

                    IconImage {
                        id: topAppIcon
                        width: 27
                        height: 27
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath(
                            topAppTile.modelData.icon || "application-x-executable",
                            "application-x-executable"
                        )
                        asynchronous: true
                    }

                    Column {
                        anchors.left: topAppIcon.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: topAppTile.modelData.name || topAppTile.modelData.id
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: String((topAppTile.modelData.categories || [])[0] || "Application").toUpperCase()
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 7
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: topAppMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        onClicked: root.launchApplication(topAppTile.modelData)
                    }
                }
            }

            Item {
                id: allApplicationsHeadingRow
                anchors.top: topAppsGrid.bottom
                anchors.topMargin: 11
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "INSTALLED APPLICATIONS"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.allApplications.length + " APPS  ·  A–Z"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }

            GridView {
                id: allAppsGrid
                anchors.top: allApplicationsHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 7
                clip: true
                cellWidth: width / (width >= 850 ? 5 : (width >= 560 ? 3 : 2))
                cellHeight: 69
                model: allApplicationsModel
                currentIndex: root.selectedIndex
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: allAppTile
                    required property var modelData
                    required property int index

                    width: allAppsGrid.cellWidth - 7
                    height: allAppsGrid.cellHeight - 6

                    Rectangle {
                        anchors.fill: parent
                        color: index === root.selectedIndex
                            ? "#171717"
                            : (allAppMouse.containsMouse ? "#111111" : "#050505")
                        border.width: 1
                        border.color: index === root.selectedIndex
                            ? "#777777"
                            : (allAppMouse.containsMouse ? "#555555" : "#282828")
                    }

                    Rectangle {
                        width: 2
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        color: "#ffffff"
                        visible: index === root.selectedIndex
                    }

                    IconImage {
                        id: allAppIcon
                        width: 26
                        height: 26
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath(
                            allAppTile.modelData.icon || "application-x-executable",
                            "application-x-executable"
                        )
                        asynchronous: true
                    }

                    Column {
                        anchors.left: allAppIcon.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: allAppTile.modelData.name || allAppTile.modelData.id
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: String((allAppTile.modelData.categories || [])[0] || "Application").toUpperCase()
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 7
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: allAppMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        onEntered: root.selectedIndex = allAppTile.index
                        onClicked: {
                            root.selectedIndex = allAppTile.index;
                            root.launchApplication(allAppTile.modelData);
                        }
                    }
                }
            }
        }

        Item {
            id: resultsHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 22
            visible: root.searchQuery.trim().length > 0 && root.launchError.length === 0

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SEARCH RESULTS"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.filteredApplications.length + " MATCHES"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
            }
        }

        Rectangle {
            anchors.top: resultsHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#333333"
            visible: resultsHeader.visible
        }

        ListView {
            id: resultsList
            anchors.top: resultsHeader.bottom
            anchors.topMargin: 7
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.searchQuery.trim().length > 0
                && root.filteredApplications.length > 0
                && root.launchError.length === 0
            clip: true
            spacing: 3
            model: filteredApplicationsModel
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: resultRow
                required property var modelData
                required property int index

                width: resultsList.width
                height: 58

                Rectangle {
                    anchors.fill: parent
                    color: index === root.selectedIndex
                        ? "#171717"
                        : (resultMouse.containsMouse ? "#101010" : "#050505")
                    border.width: 1
                    border.color: index === root.selectedIndex ? "#777777" : "#292929"
                }

                Rectangle {
                    width: 2
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: "#ffffff"
                    visible: index === root.selectedIndex
                }

                IconImage {
                    id: resultIcon
                    width: 30
                    height: 30
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    source: Quickshell.iconPath(
                        resultRow.modelData.icon || "application-x-executable",
                        "application-x-executable"
                    )
                    asynchronous: true
                }

                Column {
                    anchors.left: resultIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: resultRow.modelData.name || resultRow.modelData.id
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: resultRow.modelData.genericName || resultRow.modelData.comment || String((resultRow.modelData.categories || [])[0] || "Application")
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: resultMouse
                    z: 10
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onEntered: root.selectedIndex = resultRow.index
                    onClicked: {
                        root.selectedIndex = resultRow.index;
                        root.launchApplication(resultRow.modelData);
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: root.searchQuery.trim().length > 0
                && root.filteredApplications.length === 0
                && root.launchError.length === 0

            Text {
                width: mainContent.width - 40
                text: "NO MATCHING APPLICATIONS"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: mainContent.width - 40
                text: "Try another name, description, keyword or category."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: root.searchQuery.trim().length === 0
                && root.allApplications.length === 0
                && root.launchError.length === 0

            Text {
                width: mainContent.width - 40
                text: "NO APPLICATIONS FOUND"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: mainContent.width - 40
                text: "Installed desktop entries will appear here."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.launchError.length > 0
            text: root.launchError
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            width: Math.min(parent.width - 40, 420)
        }
    }
}
