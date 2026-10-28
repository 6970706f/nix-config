import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null
    property string activeTab: "cpu"

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color dimColor: "#686868"
    readonly property color borderColor: "#ffffff"
    readonly property color separatorColor: "#303030"
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"

    property int cpuUsage: 0
    property int cpuCores: 1
    property string cpuModel: "Detecting processor…"
    property int cpuFrequencyMhz: 0
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property int uptimeSeconds: 0
    property int processCount: 0

    property real lastCpuTotal: -1
    property real lastCpuIdle: -1

    property int memTotalKb: 0
    property int memAvailableKb: 0
    property int memFreeKb: 0
    property int memCachedKb: 0
    property int memUsedKb: 0
    property int swapTotalKb: 0
    property int swapFreeKb: 0
    property int memoryUsage: 0

    property int diskTotalKb: 0
    property int diskUsedKb: 0
    property string diskPercent: "--"
    property var topCpuProcesses: []
    property var topMemoryProcesses: []

    width: 390
    height: 460
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
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

    function openFor(tab) {
        activeTab = tab === "memory" ? "memory" : "cpu";
        visible = true;
        refreshMetrics();
    }

    function togglePanel(tab) {
        const requestedTab = tab === "memory" ? "memory" : "cpu";
        if (visible && activeTab === requestedTab) {
            closePanel();
            return;
        }
        openFor(requestedTab);
    }

    function closePanel() {
        visible = false;
    }

    function refreshMetrics() {
        if (!metricsProcess.running)
            metricsProcess.running = true;
    }

    function formatMemory(kilobytes) {
        const value = Math.max(0, Number(kilobytes) || 0);
        if (value >= 1048576)
            return (value / 1048576).toFixed(1) + " GiB";
        if (value >= 1024)
            return Math.round(value / 1024) + " MiB";
        return Math.round(value) + " KiB";
    }

    function formatUptime(seconds) {
        const value = Math.max(0, Number(seconds) || 0);
        const days = Math.floor(value / 86400);
        const hours = Math.floor((value % 86400) / 3600);
        const minutes = Math.floor((value % 3600) / 60);
        if (days > 0)
            return days + "d " + hours + "h";
        if (hours > 0)
            return hours + "h " + minutes + "m";
        return minutes + "m";
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value) || 0));
    }

    function parseMetrics(output) {
        const values = ({});
        const cpuList = [];
        const memoryList = [];
        const lines = String(output || "").split(/\r?\n/);

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].length === 0)
                continue;

            const separator = lines[i].indexOf("|");
            if (separator < 0)
                continue;

            const key = lines[i].substring(0, separator);
            const fields = lines[i].substring(separator + 1).split("|");

            if (key === "cpu_proc") {
                cpuList.push({
                    pid: fields[0] || "",
                    name: fields[1] || "unknown",
                    cpu: Number(fields[2]) || 0,
                    mem: Number(fields[3]) || 0,
                    rss: Number(fields[4]) || 0
                });
            } else if (key === "mem_proc") {
                memoryList.push({
                    pid: fields[0] || "",
                    name: fields[1] || "unknown",
                    cpu: Number(fields[2]) || 0,
                    mem: Number(fields[3]) || 0,
                    rss: Number(fields[4]) || 0
                });
            } else {
                values[key] = fields;
            }
        }

        const counters = values.cpu || [];
        if (counters.length >= 5) {
            let total = 0;
            for (let i = 0; i < counters.length; i++)
                total += Number(counters[i]) || 0;

            const idle = (Number(counters[3]) || 0) + (Number(counters[4]) || 0);
            if (lastCpuTotal >= 0 && total > lastCpuTotal) {
                const deltaTotal = total - lastCpuTotal;
                const deltaIdle = idle - lastCpuIdle;
                cpuUsage = clampPercent(Math.round((deltaTotal - deltaIdle) * 100 / deltaTotal));
            }
            lastCpuTotal = total;
            lastCpuIdle = idle;
        }

        cpuModel = (values.cpu_model && values.cpu_model[0])
            ? values.cpu_model.join("|")
            : "Processor model unavailable";
        cpuCores = Math.max(1, parseInt((values.cores || [1])[0], 10) || 1);
        cpuFrequencyMhz = Math.round(Number((values.cpu_mhz || [0])[0]) || 0);

        const load = values.load || [];
        load1 = Number(load[0]) || 0;
        load5 = Number(load[1]) || 0;
        load15 = Number(load[2]) || 0;
        uptimeSeconds = parseInt((values.uptime || [0])[0], 10) || 0;
        processCount = parseInt((values.processes || [0])[0], 10) || 0;

        memTotalKb = parseInt((values.mem_total || [0])[0], 10) || 0;
        memAvailableKb = parseInt((values.mem_available || [0])[0], 10) || 0;
        memFreeKb = parseInt((values.mem_free || [0])[0], 10) || 0;
        memCachedKb = (parseInt((values.mem_cached || [0])[0], 10) || 0)
            + (parseInt((values.mem_buffers || [0])[0], 10) || 0)
            + (parseInt((values.mem_sreclaimable || [0])[0], 10) || 0);
        memUsedKb = Math.max(0, memTotalKb - memAvailableKb);
        memoryUsage = memTotalKb > 0
            ? clampPercent(Math.round(memUsedKb * 100 / memTotalKb))
            : 0;

        swapTotalKb = parseInt((values.swap_total || [0])[0], 10) || 0;
        swapFreeKb = parseInt((values.swap_free || [0])[0], 10) || 0;

        const disk = values.disk || [];
        diskTotalKb = parseInt(disk[0] || "0", 10) || 0;
        diskUsedKb = parseInt(disk[1] || "0", 10) || 0;
        diskPercent = disk[2] || "--";

        topCpuProcesses = cpuList;
        topMemoryProcesses = memoryList;
    }

    Process {
        id: metricsProcess
        command: ["sh", "-c", `
            export LC_ALL=C

            awk '/^cpu / { printf "cpu|%s|%s|%s|%s|%s|%s|%s|%s\\n", $2,$3,$4,$5,$6,$7,$8,$9; exit }' /proc/stat
            awk '/^MemTotal:/ {print "mem_total|" $2}
                 /^MemAvailable:/ {print "mem_available|" $2}
                 /^MemFree:/ {print "mem_free|" $2}
                 /^Cached:/ {print "mem_cached|" $2}
                 /^Buffers:/ {print "mem_buffers|" $2}
                 /^SReclaimable:/ {print "mem_sreclaimable|" $2}
                 /^SwapTotal:/ {print "swap_total|" $2}
                 /^SwapFree:/ {print "swap_free|" $2}' /proc/meminfo

            awk -F: '/^model name/ { sub(/^[[:space:]]+/, "", $2); print "cpu_model|" $2; exit }' /proc/cpuinfo
            awk '/^cpu MHz/ { total += $4; count++ } END { if (count > 0) printf "cpu_mhz|%.0f\\n", total/count }' /proc/cpuinfo
            printf 'cores|%s\\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
            awk '{ printf "load|%s|%s|%s\\n", $1,$2,$3 }' /proc/loadavg
            awk '{ printf "uptime|%.0f\\n", $1 }' /proc/uptime
            ps -e --no-headers 2>/dev/null | wc -l | awk '{ printf "processes|%s\\n", $1 }'

            df -Pk / 2>/dev/null | awk 'NR == 2 { printf "disk|%s|%s|%s\\n", $2,$3,$5 }'

            ps -eo pid=,comm=,%cpu=,%mem=,rss= --sort=-pcpu 2>/dev/null |
            awk 'NR <= 5 {
                pid=$1; cpu=$(NF-2); mem=$(NF-1); rss=$NF; name="";
                for (i=2; i<=NF-3; i++) name=name (name == "" ? "" : " ") $i;
                printf "cpu_proc|%s|%s|%s|%s|%s\\n", pid,name,cpu,mem,rss
            }'

            ps -eo pid=,comm=,%cpu=,%mem=,rss= --sort=-pmem 2>/dev/null |
            awk 'NR <= 5 {
                pid=$1; cpu=$(NF-2); mem=$(NF-1); rss=$NF; name="";
                for (i=2; i<=NF-3; i++) name=name (name == "" ? "" : " ") $i;
                printf "mem_proc|%s|%s|%s|%s|%s\\n", pid,name,cpu,mem,rss
            }'
        `]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.parseMetrics(this.text)
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: root.refreshMetrics()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    Rectangle {
        id: outerBorder
        focus: root.visible
        anchors.fill: parent
        color: root.panelColor
        radius: 0
        border.width: 1
        border.color: root.borderColor

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 0

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰻠  SYSTEM MONITOR"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.bold: false
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.activeTab === "cpu" ? "CPU / LIVE" : "MEMORY / LIVE"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignRight
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Row {
                id: tabBar
                width: parent.width
                height: 30

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: root.activeTab === "cpu"
                        ? "#111111" : (cpuTabMouse.containsMouse ? "#080808" : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "CPU"
                        color: root.activeTab === "cpu" ? root.foregroundColor : root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: false
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.activeTab === "cpu" ? 2 : 1
                        color: root.activeTab === "cpu" ? "#ffffff" : root.separatorColor
                    }

                    MouseArea {
                        id: cpuTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "cpu"
                    }
                }

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: root.activeTab === "memory"
                        ? "#111111" : (memoryTabMouse.containsMouse ? "#080808" : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "MEMORY"
                        color: root.activeTab === "memory" ? root.foregroundColor : root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: false
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.activeTab === "memory" ? 2 : 1
                        color: root.activeTab === "memory" ? "#ffffff" : root.separatorColor
                    }

                    MouseArea {
                        id: memoryTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "memory"
                    }
                }
            }

            Item {
                width: parent.width
                height: 6
            }

            Column {
                id: cpuPage
                visible: root.activeTab === "cpu"
                width: parent.width
                spacing: 7

                Item {
                    width: parent.width
                    height: 58

                    Text {
                        id: cpuPercentText
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: root.cpuUsage + "%"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 26
                        font.bold: false
                    }

                    Column {
                        anchors.left: cpuPercentText.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 2

                        Text {
                            text: "TOTAL CPU USAGE"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: false
                        }

                        Text {
                            width: parent.width
                            text: root.cpuCores + " logical cores · sampled live"
                            color: root.dimColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 5
                        color: "#242424"

                        Rectangle {
                            width: parent.width * root.clampPercent(root.cpuUsage) / 100
                            height: parent.height
                            color: root.foregroundColor
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 49
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "CORES", value: String(root.cpuCores) },
                            { label: "LOAD / 1M", value: root.load1.toFixed(2) },
                            { label: "PROCESSES", value: String(root.processCount) }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 12) / 3
                            height: parent.height
                            color: "#080808"
                            border.width: 1
                            border.color: root.separatorColor

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: root.dimColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.value
                                    color: root.foregroundColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.bold: false
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 20

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.cpuModel
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        width: parent.width - 5
                        elide: Text.ElideRight
                    }
                }

                Item {
                    width: parent.width
                    height: 15

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "LOAD  " + root.load1.toFixed(2) + " / "
                            + root.load5.toFixed(2) + " / " + root.load15.toFixed(2)
                            + "     UPTIME  " + root.formatUptime(root.uptimeSeconds)
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.separatorColor
                }

                Item {
                    width: parent.width
                    height: 15

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TOP PROCESSES  /  CPU"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: false
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CPU · RSS"
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.topCpuProcesses

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 30
                            color: "#000000"
                            clip: true

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                spacing: 7

                                Text {
                                    width: 34
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.pid
                                    color: "#9a9a9a"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Item {
                                    width: Math.max(60, parent.width - 14 - 34 - 45 - 58 - 21)
                                    height: parent.height

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.topMargin: 4
                                        height: 12
                                        text: String(modelData.name || "unknown")
                                        color: "#f2f2f2"
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        height: 2
                                        color: "#383838"

                                        Rectangle {
                                            width: parent.width * root.clampPercent(Number(modelData.cpu)) / 100
                                            height: parent.height
                                            color: "#f2f2f2"
                                        }
                                    }
                                }

                                Text {
                                    width: 45
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Number(modelData.cpu).toFixed(1) + "%"
                                    color: "#f2f2f2"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    width: 58
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.formatMemory(modelData.rss)
                                    color: "#c0c0c0"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: "#292929"
                            }
                        }
                    }
                    Text {
                        visible: root.topCpuProcesses.length === 0
                        width: parent.width
                        height: 22
                        text: "Waiting for process data…"
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Item {
                    width: parent.width
                    height: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.cpuFrequencyMhz > 0
                            ? "AVG FREQUENCY  " + root.cpuFrequencyMhz + " MHz"
                            : "CPU frequency unavailable"
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }
            }

            Column {
                id: memoryPage
                visible: root.activeTab === "memory"
                width: parent.width
                spacing: 7

                Item {
                    width: parent.width
                    height: 58

                    Text {
                        id: memoryUsedText
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: root.formatMemory(root.memUsedKb)
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 23
                        font.bold: false
                    }

                    Column {
                        anchors.left: memoryUsedText.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 2

                        Text {
                            text: "RAM IN USE"
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: false
                        }

                        Text {
                            width: parent.width
                            text: root.memoryUsage + "% of " + root.formatMemory(root.memTotalKb)
                            color: root.dimColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 5
                        color: "#242424"

                        Rectangle {
                            width: parent.width * root.clampPercent(root.memoryUsage) / 100
                            height: parent.height
                            color: root.foregroundColor
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 49
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "AVAILABLE", value: root.formatMemory(root.memAvailableKb) },
                            { label: "FREE", value: root.formatMemory(root.memFreeKb) },
                            { label: "CACHE", value: root.formatMemory(root.memCachedKb) }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 12) / 3
                            height: parent.height
                            color: "#080808"
                            border.width: 1
                            border.color: root.separatorColor

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: root.dimColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.value
                                    color: root.foregroundColor
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.bold: false
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 31

                    Column {
                        anchors.fill: parent
                        spacing: 5

                        Row {
                            width: parent.width
                            height: 13

                            Text {
                                anchors.left: parent.left
                                text: "SWAP"
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 9
                            }

                            Text {
                                anchors.right: parent.right
                                text: root.formatMemory(Math.max(0, root.swapTotalKb - root.swapFreeKb))
                                    + " / " + root.formatMemory(root.swapTotalKb)
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 4
                            color: "#242424"

                            Rectangle {
                                width: parent.width * (root.swapTotalKb > 0
                                    ? root.clampPercent((root.swapTotalKb - root.swapFreeKb) * 100 / root.swapTotalKb)
                                    : 0) / 100
                                height: parent.height
                                color: root.foregroundColor
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 15

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ROOT DISK  " + root.formatMemory(root.diskUsedKb) + " / "
                            + root.formatMemory(root.diskTotalKb) + "  ·  " + root.diskPercent
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.separatorColor
                }

                Item {
                    width: parent.width
                    height: 15

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TOP PROCESSES  /  MEMORY"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: false
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RAM · CPU"
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.topMemoryProcesses

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 30
                            color: "#000000"
                            clip: true

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                spacing: 7

                                Text {
                                    width: 34
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.pid
                                    color: "#9a9a9a"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Item {
                                    width: Math.max(60, parent.width - 14 - 34 - 45 - 58 - 21)
                                    height: parent.height

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.topMargin: 4
                                        height: 12
                                        text: String(modelData.name || "unknown")
                                        color: "#f2f2f2"
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        height: 2
                                        color: "#383838"

                                        Rectangle {
                                            width: parent.width * root.clampPercent(Number(modelData.mem)) / 100
                                            height: parent.height
                                            color: "#f2f2f2"
                                        }
                                    }
                                }

                                Text {
                                    width: 45
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Number(modelData.mem).toFixed(1) + "%"
                                    color: "#f2f2f2"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    width: 58
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.formatMemory(modelData.rss)
                                    color: "#c0c0c0"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: "#292929"
                            }
                        }
                    }
                    Text {
                        visible: root.topMemoryProcesses.length === 0
                        width: parent.width
                        height: 22
                        text: "Waiting for process data…"
                        color: root.dimColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
