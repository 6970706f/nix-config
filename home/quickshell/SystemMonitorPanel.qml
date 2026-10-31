import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null
    property string activeTab: "cpu"


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

    width: 390 + Theme.popupPadX * 2
    height: 524 + Theme.popupPadY
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
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

    readonly property color tabAccent: root.activeTab === "cpu" ? Theme.iris : Theme.foam

    PanelSurface {
        id: outerBorder
        window: root
        accent: root.tabAccent

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 10

            PanelHeader {
                glyph: root.activeTab === "cpu" ? Theme.icons.cpu : Theme.icons.memory
                accent: root.tabAccent
                title: "System monitor"
                subtitle: "Up " + root.formatUptime(root.uptimeSeconds) + "  ·  " + root.processCount + " processes"

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Theme.mint

                    SequentialAnimation on opacity {
                        running: root.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Live"
                    color: Theme.subtle
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            SegmentTabs {
                id: tabBar
                accent: root.tabAccent
                current: root.activeTab
                tabs: [
                    { key: "cpu", label: "CPU" },
                    { key: "memory", label: "Memory" }
                ]
                onPicked: function(key) { root.activeTab = key; }
            }

            Column {
                id: cpuPage
                visible: root.activeTab === "cpu"
                width: parent.width
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 100
                    radius: 18
                    color: Theme.surface

                    RingGauge {
                        id: cpuRing
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 78
                        height: 78
                        thickness: 8
                        value: root.clampPercent(root.cpuUsage)
                        accent: Theme.levelColor(root.cpuUsage, Theme.iris)

                        UiText {
                            anchors.centerIn: parent
                            text: root.cpuUsage + "%"
                            font.family: Theme.displayFont
                            font.pixelSize: 19
                            font.weight: Font.Bold
                        }
                    }

                    Column {
                        anchors.left: cpuRing.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        UiText {
                            width: parent.width
                            text: "Total CPU usage"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }

                        UiText {
                            width: parent.width
                            text: root.cpuModel
                            color: Theme.subtle
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        UiText {
                            width: parent.width
                            text: root.cpuFrequencyMhz > 0
                                ? "Average " + root.cpuFrequencyMhz + " MHz"
                                : "CPU frequency unavailable"
                            color: Theme.subtle
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "Cores", value: String(root.cpuCores) },
                            { label: "Load 1m", value: root.load1.toFixed(2) },
                            { label: "Load 5m", value: root.load5.toFixed(2) },
                            { label: "Load 15m", value: root.load15.toFixed(2) }
                        ]

                        delegate: StatTile {
                            required property var modelData
                            width: (parent.width - 24) / 4
                            label: modelData.label
                            value: modelData.value
                        }
                    }
                }

                UiText {
                    height: 16
                    text: "Top processes by CPU"
                    color: Theme.subtle
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Column {
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: root.topCpuProcesses

                        delegate: ProcessRow {
                            required property var modelData
                            pid: modelData.pid
                            name: String(modelData.name || "unknown")
                            percent: Number(modelData.cpu)
                            memory: root.formatMemory(modelData.rss)
                            accent: Theme.iris
                        }
                    }

                    UiText {
                        visible: root.topCpuProcesses.length === 0
                        width: parent.width
                        height: 22
                        text: "Waiting for process data…"
                        color: Theme.subtle
                        font.pixelSize: 11
                    }
                }
            }

            Column {
                id: memoryPage
                visible: root.activeTab === "memory"
                width: parent.width
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 100
                    radius: 18
                    color: Theme.surface

                    RingGauge {
                        id: memoryRing
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 78
                        height: 78
                        thickness: 8
                        value: root.clampPercent(root.memoryUsage)
                        accent: Theme.levelColor(root.memoryUsage, Theme.foam)

                        UiText {
                            anchors.centerIn: parent
                            text: root.memoryUsage + "%"
                            font.family: Theme.displayFont
                            font.pixelSize: 19
                            font.weight: Font.Bold
                        }
                    }

                    Column {
                        anchors.left: memoryRing.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        UiText {
                            width: parent.width
                            text: root.formatMemory(root.memUsedKb) + " in use"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }

                        UiText {
                            width: parent.width
                            text: "of " + root.formatMemory(root.memTotalKb) + " RAM"
                            color: Theme.subtle
                            font.pixelSize: 10
                        }

                        UiText {
                            width: parent.width
                            text: "Root disk " + root.formatMemory(root.diskUsedKb) + " / "
                                + root.formatMemory(root.diskTotalKb) + "  ·  " + root.diskPercent
                            color: Theme.subtle
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "Available", value: root.formatMemory(root.memAvailableKb) },
                            { label: "Free", value: root.formatMemory(root.memFreeKb) },
                            { label: "Cache", value: root.formatMemory(root.memCachedKb) }
                        ]

                        delegate: StatTile {
                            required property var modelData
                            width: (parent.width - 16) / 3
                            label: modelData.label
                            value: modelData.value
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 16

                    UiText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Top processes by memory"
                        color: Theme.subtle
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MeterBar {
                        anchors.right: swapLabel.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 5
                        accent: Theme.foam
                        value: root.swapTotalKb > 0
                            ? (root.swapTotalKb - root.swapFreeKb) / root.swapTotalKb
                            : 0
                    }

                    UiText {
                        id: swapLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Swap " + root.formatMemory(Math.max(0, root.swapTotalKb - root.swapFreeKb))
                            + " / " + root.formatMemory(root.swapTotalKb)
                        color: Theme.subtle
                        font.pixelSize: 10
                    }
                }

                Column {
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: root.topMemoryProcesses

                        delegate: ProcessRow {
                            required property var modelData
                            pid: modelData.pid
                            name: String(modelData.name || "unknown")
                            percent: Number(modelData.mem)
                            memory: root.formatMemory(modelData.rss)
                            accent: Theme.foam
                        }
                    }

                    UiText {
                        visible: root.topMemoryProcesses.length === 0
                        width: parent.width
                        height: 22
                        text: "Waiting for process data…"
                        color: Theme.subtle
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
