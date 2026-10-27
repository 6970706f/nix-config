import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color borderColor: "#ffffff"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    property bool networkManagerAvailable: true
    property string activeTab: "wifi"
    property bool wifiEnabled: false
    property string wifiDevice: ""
    property string wifiState: "unavailable"
    property string wifiConnection: ""
    property string wifiSignal: ""
    property string wifiIp: ""

    property string ethernetDevice: ""
    property string ethernetState: "unavailable"
    property string ethernetIp: ""
    property string connectivity: "unknown"

    property var wifiNetworks: []
    property bool statusLoading: false
    property bool scanLoading: false
    property bool busy: false
    property string busyLabel: ""
    property string statusMessage: ""
    property string errorMessage: ""

    property bool passwordPromptVisible: false
    property string passwordInput: ""
    property string pendingTarget: ""
    property string pendingRawSsid: ""
    property string pendingBssid: ""
    property string pendingDisplayName: ""
    property string pendingSecurity: ""
    property bool pendingProtected: false

    width: 390
    height: activeTab === "wifi" ? (passwordPromptVisible ? 390 : 345) : 260
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

    function openPanel() {
        errorMessage = "";
        statusMessage = "";
        passwordPromptVisible = false;
        passwordInput = "";
        visible = true;
        refreshStatus();
    }

    onVisibleChanged: {
        if (!root.visible) {
            root.passwordPromptVisible = false;
            root.passwordInput = "";
        }
    }

    function closePanel() {
        visible = false;
    }

    function togglePanel() {
        if (visible)
            closePanel();
        else
            openPanel();
    }

    function refreshStatus() {
        if (statusProcess.running || actionProcess.running)
            return;
        statusLoading = true;
        statusProcess.running = true;
    }

    function parseStatusOutput(output, exitCode) {
        const values = ({});
        const lines = String(output || "").split(/\r?\n/);

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const separator = line.indexOf("|");
            if (separator < 0)
                continue;
            values[line.substring(0, separator)] = line.substring(separator + 1);
        }

        if (exitCode !== 0 || values.error) {
            networkManagerAvailable = false;
            wifiEnabled = false;
            wifiDevice = "";
            wifiState = "unavailable";
            wifiConnection = "";
            wifiSignal = "";
            wifiIp = "";
            ethernetDevice = "";
            ethernetState = "unavailable";
            ethernetIp = "";
            connectivity = "unknown";
            wifiNetworks = [];
            errorMessage = values.error || "NetworkManager did not respond. Check whether the service is running.";
            return;
        }

        networkManagerAvailable = true;
        wifiEnabled = values.wifi_radio === "enabled";
        wifiDevice = values.wifi_device || "";
        wifiState = values.wifi_state || "unavailable";
        wifiConnection = values.wifi_connection || "";
        wifiSignal = values.wifi_signal || "";
        wifiIp = values.wifi_ip || "";
        ethernetDevice = values.ethernet_device || "";
        ethernetState = values.ethernet_state || "unavailable";
        ethernetIp = values.ethernet_ip || "";
        connectivity = values.connectivity || "unknown";

        if (wifiEnabled && wifiDevice.length > 0)
            refreshNetworks(false);
        else {
            wifiNetworks = [];
            scanLoading = false;
        }
    }

    function splitNmcliFields(line) {
        const fields = [];
        let current = "";
        let escaped = false;

        for (let i = 0; i < line.length; i++) {
            const character = line.charAt(i);
            if (escaped) {
                current += character;
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === ":") {
                fields.push(current);
                current = "";
            } else {
                current += character;
            }
        }

        if (escaped)
            current += "\\";
        fields.push(current);
        return fields;
    }

    function parseWifiNetworks(output) {
        const entries = [];
        const lines = String(output || "").split(/\r?\n/);

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].length === 0)
                continue;

            const fields = splitNmcliFields(lines[i]);
            if (fields.length < 5)
                continue;

            const inUse = fields[0] === "*";
            const bssid = fields[1] || "";
            const rawSsid = fields[2] || "";
            const hidden = rawSsid.length === 0 || rawSsid === "--";
            const security = fields.slice(4).join(":") || "--";
            const parsedSignal = parseInt(fields[3], 10);
            const signal = isNaN(parsedSignal) ? 0 : parsedSignal;
            const ssid = hidden ? "Hidden network" : rawSsid;
            const entry = {
                ssid: ssid,
                rawSsid: rawSsid,
                bssid: bssid,
                signal: signal,
                security: security,
                inUse: inUse,
                hidden: hidden
            };

            let existingIndex = -1;
            for (let j = 0; j < entries.length; j++) {
                const sameNetwork = entries[j].rawSsid === rawSsid
                    && entries[j].security === security
                    && (!hidden || entries[j].bssid === bssid);
                if (sameNetwork) {
                    existingIndex = j;
                    break;
                }
            }

            if (existingIndex < 0)
                entries.push(entry);
            else if (entry.inUse || (!entries[existingIndex].inUse && entry.signal > entries[existingIndex].signal))
                entries[existingIndex] = entry;
        }

        entries.sort(function(a, b) {
            if (a.inUse !== b.inUse)
                return a.inUse ? -1 : 1;
            if (a.signal !== b.signal)
                return b.signal - a.signal;
            return a.ssid.localeCompare(b.ssid);
        });
        return entries;
    }

    function refreshNetworks(forceRescan) {
        if (!networkManagerAvailable || !wifiEnabled || wifiDevice.length === 0) {
            wifiNetworks = [];
            scanLoading = false;
            return;
        }
        if (busy || statusLoading || scanProcess.running)
            return;

        errorMessage = "";
        scanLoading = true;
        scanProcess.exec([
            "nmcli", "--terse", "--escape", "yes",
            "--fields", "IN-USE,BSSID,SSID,SIGNAL,SECURITY",
            "device", "wifi", "list",
            "--rescan", forceRescan ? "yes" : "no",
            "ifname", wifiDevice
        ]);
    }

    function startAction(command, label, environment) {
        if (busy || actionProcess.running)
            return false;
        if (statusLoading || scanLoading || statusProcess.running || scanProcess.running) {
            statusMessage = "Wait for the network query to finish.";
            return false;
        }

        errorMessage = "";
        statusMessage = label;
        busyLabel = label;
        busy = true;
        const processEnvironment = environment || ({ LC_ALL: "C" });
        actionProcess.exec({
            command: command,
            environment: processEnvironment
        });
        return true;
    }

    function setWifiEnabled(enabled) {
        startAction(
            ["nmcli", "radio", "wifi", enabled ? "on" : "off"],
            enabled ? "Enabling Wi-Fi…" : "Disabling Wi-Fi…"
        );
    }

    function disconnectWifi() {
        if (wifiDevice.length === 0)
            return;
        startAction(["nmcli", "device", "disconnect", wifiDevice], "Disconnecting Wi-Fi…");
    }

    function toggleEthernet() {
        if (ethernetDevice.length === 0)
            return;
        if (ethernetConnected())
            startAction(["nmcli", "device", "disconnect", ethernetDevice], "Disconnecting Ethernet…");
        else
            startAction(["nmcli", "device", "connect", ethernetDevice], "Enabling Ethernet…");
    }

    function handleNetworkClick(network) {
        if (busy || scanLoading || statusLoading || network.inUse)
            return;
        if (network.hidden) {
            errorMessage = "Hidden networks require an SSID; this panel does not support that flow yet.";
            return;
        }
        if (!network.bssid && !network.rawSsid) {
            errorMessage = "This network did not provide a valid identifier.";
            return;
        }

        const securityName = String(network.security || "").toUpperCase();
        if (securityName.indexOf("802.1X") >= 0 || securityName.indexOf("8021X") >= 0 || securityName.indexOf("EAP") >= 0 || securityName.indexOf("WEP") >= 0) {
            errorMessage = "This panel supports open and WPA/WPA2/WPA3-Personal networks; WEP and 802.1X require additional configuration.";
            return;
        }

        pendingTarget = network.bssid || network.rawSsid;
        pendingRawSsid = network.rawSsid;
        pendingBssid = network.bssid;
        pendingDisplayName = network.ssid;
        pendingSecurity = network.security;
        pendingProtected = network.security !== "--" && network.security.length > 0;

        if (pendingProtected) {
            passwordInput = "";
            passwordPromptVisible = true;
            Qt.callLater(function() { passwordField.forceActiveFocus(); });
        } else {
            connectToPendingNetwork("");
        }
    }

    function submitPassword() {
        if (passwordInput.length === 0) {
            errorMessage = "Enter the network password.";
            return;
        }

        const password = passwordInput;
        passwordInput = "";
        passwordPromptVisible = false;
        connectToPendingNetwork(password);
    }

    function connectToPendingNetwork(password) {
        if (!networkManagerAvailable || !wifiEnabled || wifiDevice.length === 0) {
            errorMessage = "Enable Wi-Fi and check that an adapter is available.";
            passwordInput = "";
            passwordPromptVisible = false;
            return;
        }

        if (!pendingProtected) {
            startAction(
                ["nmcli", "--wait", "25", "device", "wifi", "connect", pendingTarget, "ifname", wifiDevice],
                "Connecting to " + pendingDisplayName + "…"
            );
            passwordInput = "";
            return;
        }

        const profileSuffix = String(pendingTarget).replace(/[^A-Za-z0-9_-]/g, "").substring(0, 24);
        const profileName = "quickshell-panel-temp-" + (profileSuffix || String(Date.now()));
        const secureConnectScript = `
            set -eu
            IFS= read -r NETWORK_PASSWORD
            umask 077
            runtime_dir="\${XDG_RUNTIME_DIR:-/tmp}"
            password_file=$(mktemp "$runtime_dir/quickshell-wifi-pass.XXXXXX")
            trap 'rm -f "$password_file"' EXIT
            printf '802-11-wireless-security.psk:%s\\n' "$NETWORK_PASSWORD" > "$password_file"
            unset NETWORK_PASSWORD

            connection_uuid=$(nmcli -g UUID connection show "$NETWORK_PROFILE" 2>/dev/null | head -n 1)
            if [ -z "$connection_uuid" ]; then
                nmcli connection add save no type wifi con-name "$NETWORK_PROFILE" ifname "$NETWORK_IFACE" ssid "$NETWORK_SSID" connection.autoconnect no wifi-sec.key-mgmt "$NETWORK_KEY_MGMT" wifi-sec.psk-flags 2 >/dev/null
                connection_uuid=$(nmcli -g UUID connection show "$NETWORK_PROFILE" 2>/dev/null | head -n 1)
            fi
            if [ -z "$connection_uuid" ]; then
                printf 'Could not prepare the temporary Wi-Fi profile.\\n' >&2
                exit 1
            fi

            nmcli connection modify --temporary uuid "$connection_uuid" connection.autoconnect no wifi-sec.psk-flags 2
            if [ -n "$NETWORK_BSSID" ]; then
                nmcli --wait 25 connection up uuid "$connection_uuid" ifname "$NETWORK_IFACE" ap "$NETWORK_BSSID" passwd-file "$password_file"
            else
                nmcli --wait 25 connection up uuid "$connection_uuid" ifname "$NETWORK_IFACE" passwd-file "$password_file"
            fi
        `;

        const actionStarted = startAction(
            ["sh", "-c", secureConnectScript],
            "Connecting to " + pendingDisplayName + "…",
            ({
                LC_ALL: "C",
                NETWORK_PROFILE: profileName,
                NETWORK_IFACE: wifiDevice,
                NETWORK_SSID: pendingTargetSsid(),
                NETWORK_BSSID: pendingTargetBssid(),
                NETWORK_KEY_MGMT: String(pendingSecurity).toUpperCase().indexOf("WPA3") >= 0
                    && String(pendingSecurity).toUpperCase().indexOf("WPA2") < 0 ? "sae" : "wpa-psk"
            })
        );
        passwordInput = "";
        if (actionStarted)
            actionProcess.write(String(password || "") + "\n");
    }

    function pendingTargetSsid() {
        return pendingRawSsid;
    }

    function pendingTargetBssid() {
        return pendingBssid;
    }

    function wifiConnected() {
        return wifiState.indexOf("connected") === 0;
    }

    function currentWifiName() {
        for (let i = 0; i < wifiNetworks.length; i++) {
            if (wifiNetworks[i].inUse)
                return wifiNetworks[i].ssid;
        }
        return wifiConnection && wifiConnection !== "--" ? wifiConnection : "current network";
    }

    function ethernetConnected() {
        return ethernetState.indexOf("connected") === 0;
    }

    function connectivityLabel() {
        if (connectivity === "full")
            return "Internet available";
        if (connectivity === "limited")
            return "Limited internet access";
        if (connectivity === "portal")
            return "Captive portal detected";
        if (connectivity === "none")
            return "No internet access detected";
        return "Internet status unknown";
    }

    function wifiStateLabel() {
        if (!networkManagerAvailable)
            return "NetworkManager unavailable";
        if (!wifiDevice)
            return "Adapter not detected";
        if (!wifiEnabled)
            return "Disabled";
        if (wifiConnected())
            return "Connected";
        if (wifiState.indexOf("connecting") === 0)
            return "Connecting…";
        if (wifiState.indexOf("unavailable") === 0)
            return "Unavailable";
        return "Disconnected";
    }

    function ethernetStateLabel() {
        if (!networkManagerAvailable)
            return "NetworkManager unavailable";
        if (!ethernetDevice)
            return "Interface not detected";
        if (ethernetConnected()) {
            if (connectivity === "none")
                return "Connected · no internet access detected";
            if (connectivity === "limited")
                return "Connected · limited access";
            if (connectivity === "portal")
                return "Connected · captive portal";
            if (connectivity === "unknown")
                return "Connected · internet status unknown";
            return "Connected";
        }
        if (ethernetState.indexOf("connecting") === 0)
            return "Connecting…";
        if (ethernetState.indexOf("unavailable") === 0)
            return "Unavailable · check the cable";
        return "Disconnected";
    }

    function shortOperationError(rawOutput) {
        const details = String(rawOutput || "").trim();
        const lower = details.toLowerCase();
        if (lower.indexOf("secrets were required") >= 0 || lower.indexOf("no agents were available") >= 0)
            return "Could not obtain network credentials.";
        if (lower.indexOf("not authorized") >= 0 || lower.indexOf("permission denied") >= 0)
            return "Operation denied by system permissions.";
        if (lower.indexOf("no network with ssid") >= 0 || lower.indexOf("no suitable device") >= 0)
            return "Network or adapter unavailable.";
        if (details.length === 0)
            return "The operation failed. Check NetworkManager and system permissions.";
        return details.length > 150 ? details.substring(0, 147) + "…" : details;
    }

    Process {
        id: statusProcess
        command: ["sh", "-c", `
            export LC_ALL=C
            if ! command -v nmcli >/dev/null 2>&1; then
                printf 'error|nmcli not found\\n'
                exit 127
            fi

            nm_running=$(nmcli -g RUNNING general 2>/dev/null)
            if [ "$nm_running" != "running" ]; then
                printf 'error|NetworkManager unavailable or stopped\\n'
                exit 1
            fi

            wifi_radio=$(nmcli -g WIFI radio 2>/dev/null | head -n 1)
            device_status=$(nmcli --terse --escape no --fields DEVICE,TYPE,STATE device status 2>/dev/null)
            wifi_device=$(printf '%s\\n' "$device_status" | awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')
            if [ -z "$wifi_device" ]; then
                wifi_device=$(printf '%s\\n' "$device_status" | awk -F: '$2 == "wifi" { print $1; exit }')
            fi
            ethernet_device=$(printf '%s\\n' "$device_status" | awk -F: '$2 == "ethernet" && $3 ~ /^connected/ { print $1; exit }')
            if [ -z "$ethernet_device" ]; then
                ethernet_device=$(printf '%s\\n' "$device_status" | awk -F: '$2 == "ethernet" { print $1; exit }')
            fi

            wifi_state=""
            wifi_connection=""
            wifi_signal=""
            wifi_ip=""
            if [ -n "$wifi_device" ]; then
                wifi_state=$(printf '%s\\n' "$device_status" | awk -F: -v dev="$wifi_device" '$1 == dev && $2 == "wifi" { print $3; exit }')
                wifi_connection=$(nmcli -g GENERAL.CONNECTION device show "$wifi_device" 2>/dev/null | head -n 1)
                wifi_signal=$(nmcli --terse --escape no --fields IN-USE,SIGNAL device wifi list --rescan no ifname "$wifi_device" 2>/dev/null | awk -F: '$1 == "*" { print $2; exit }')
                wifi_ip=$(nmcli -g IP4.ADDRESS device show "$wifi_device" 2>/dev/null | head -n 1 | cut -d/ -f1)
            fi

            ethernet_state=""
            ethernet_ip=""
            if [ -n "$ethernet_device" ]; then
                ethernet_state=$(printf '%s\\n' "$device_status" | awk -F: -v dev="$ethernet_device" '$1 == dev && $2 == "ethernet" { print $3; exit }')
                ethernet_ip=$(nmcli -g IP4.ADDRESS device show "$ethernet_device" 2>/dev/null | head -n 1 | cut -d/ -f1)
            fi

            connectivity=$(nmcli -g CONNECTIVITY general 2>/dev/null | head -n 1)
            printf 'wifi_radio|%s\\n' "\${wifi_radio:-unknown}"
            printf 'wifi_device|%s\\n' "$wifi_device"
            printf 'wifi_state|%s\\n' "$wifi_state"
            printf 'wifi_connection|%s\\n' "$wifi_connection"
            printf 'wifi_signal|%s\\n' "$wifi_signal"
            printf 'wifi_ip|%s\\n' "$wifi_ip"
            printf 'ethernet_device|%s\\n' "$ethernet_device"
            printf 'ethernet_state|%s\\n' "$ethernet_state"
            printf 'ethernet_ip|%s\\n' "$ethernet_ip"
            printf 'connectivity|%s\\n' "\${connectivity:-unknown}"
        `]
        stdout: StdioCollector {
            id: statusOutput
        }
        onExited: function(exitCode, exitStatus) {
            root.statusLoading = false;
            root.parseStatusOutput(statusOutput.text, exitCode);
        }
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            id: scanOutput
        }
        stderr: StdioCollector {
            id: scanErrors
        }
        onExited: function(exitCode, exitStatus) {
            root.scanLoading = false;
            if (exitCode === 0) {
                root.wifiNetworks = root.parseWifiNetworks(scanOutput.text);
            } else if (root.wifiEnabled && root.networkManagerAvailable) {
                root.errorMessage = "Could not list Wi-Fi networks.";
            }
        }
    }

    Process {
        id: actionProcess
        stdinEnabled: true
        stdout: StdioCollector {
            id: actionOutput
        }
        stderr: StdioCollector {
            id: actionErrors
        }
        onExited: function(exitCode, exitStatus) {
            root.busy = false;
            actionProcess.environment = ({ LC_ALL: "C" });
            root.passwordInput = "";
            if (exitCode === 0) {
                root.errorMessage = "";
                root.statusMessage = root.busyLabel.replace(/…$/, "") + " completed.";
            } else {
                root.errorMessage = root.shortOperationError(actionErrors.text || actionOutput.text);
                root.statusMessage = "";
            }
            Qt.callLater(function() { root.refreshStatus(); });
        }
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
                    id: networkTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰖩  NETWORK"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusLoading ? "REFRESHING" : (root.busy ? "WORKING" : "")
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#303030"
            }

            Row {
                id: tabBar
                width: parent.width
                height: 30

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: root.activeTab === "wifi" ? "#111111" : (wifiTabMouse.containsMouse ? "#080808" : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "WI-FI"
                        color: root.activeTab === "wifi" ? root.foregroundColor : root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: root.activeTab === "wifi"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.activeTab === "wifi" ? 2 : 1
                        color: root.activeTab === "wifi" ? "#ffffff" : "#303030"
                    }

                    MouseArea {
                        id: wifiTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "wifi"
                    }
                }

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: root.activeTab === "ethernet" ? "#111111" : (ethernetTabMouse.containsMouse ? "#080808" : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "ETHERNET"
                        color: root.activeTab === "ethernet" ? root.foregroundColor : root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: root.activeTab === "ethernet"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.activeTab === "ethernet" ? 2 : 1
                        color: root.activeTab === "ethernet" ? "#ffffff" : "#303030"
                    }

                    MouseArea {
                        id: ethernetTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "ethernet"
                    }
                }
            }

            Column {
                id: wifiPage
                visible: root.activeTab === "wifi"
                width: parent.width
                spacing: 5

                Row {
                    width: parent.width
                    height: 21
                    spacing: 7

                    Text {
                        text: "WI-FI"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.wifiStateLabel()
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: parent.width - 70
                    }
                }

                Row {
                    width: parent.width
                    height: 28
                    spacing: 7

                    Rectangle {
                        width: 86
                        height: parent.height
                        radius: 0
                        color: wifiToggleMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                        border.width: 1
                        border.color: "#373737"
                        opacity: root.busy || root.statusLoading || root.scanLoading ? 0.5 : 1

                        Text {
                            anchors.centerIn: parent
                            text: root.wifiEnabled ? "Wi-Fi ON" : "Wi-Fi OFF"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }

                        MouseArea {
                            id: wifiToggleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.networkManagerAvailable && !root.busy && !root.statusLoading && !root.scanLoading
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setWifiEnabled(!root.wifiEnabled)
                        }
                    }

                    Rectangle {
                        width: 91
                        height: parent.height
                        visible: root.wifiConnected()
                        radius: 0
                        color: wifiDisconnectMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                        border.width: 1
                        border.color: "#373737"
                        opacity: root.busy || root.statusLoading || root.scanLoading ? 0.5 : 1

                        Text {
                            anchors.centerIn: parent
                            text: "Disconnect"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }

                        MouseArea {
                            id: wifiDisconnectMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.networkManagerAvailable && !root.busy && !root.statusLoading && !root.scanLoading
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.disconnectWifi()
                        }
                    }

                    Rectangle {
                        width: 94
                        height: parent.height
                        radius: 0
                        color: refreshMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                        border.width: 1
                        border.color: "#373737"
                        opacity: root.busy || root.statusLoading || root.scanLoading ? 0.5 : 1

                        Text {
                            anchors.centerIn: parent
                            text: root.scanLoading ? "Scanning…" : "↻ Refresh"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.networkManagerAvailable && root.wifiEnabled && !root.busy && !root.statusLoading && !root.scanLoading
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshNetworks(true)
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 19
                    text: root.wifiConnected()
                        ? "Connected: " + root.currentWifiName()
                        : "No Wi-Fi network connected"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                ListView {
                    id: wifiList
                    width: parent.width
                    height: root.passwordPromptVisible ? 78 : 118
                    clip: true
                    spacing: 3
                    model: root.wifiNetworks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: networkRow
                        required property var modelData
                        width: wifiList.width
                        height: 27
                        radius: 0
                        color: modelData.inUse ? "#1a1a1a" : (networkRowMouse.containsMouse ? "#101010" : "transparent")
                        border.width: modelData.inUse ? 1 : 0
                        border.color: "#454545"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                width: parent.width - 105
                                height: parent.height
                                text: networkRow.modelData.ssid
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                width: 72
                                height: parent.height
                                text: (networkRow.modelData.signal > 0 ? networkRow.modelData.signal + "%" : "--")
                                    + (networkRow.modelData.security === "--" ? "" : "  󰌾")
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                width: 18
                                height: parent.height
                                text: networkRow.modelData.inUse ? "✓" : ""
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: networkRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.busy && !root.scanLoading && !root.statusLoading && !networkRow.modelData.inUse
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.handleNetworkClick(networkRow.modelData)
                        }
                    }
                }

                Text {
                    visible: root.scanLoading || (root.wifiEnabled && root.wifiDevice.length > 0 && root.wifiNetworks.length === 0)
                    width: parent.width
                    height: 14
                    text: root.scanLoading ? "Scanning for available networks…" : "No networks found. Refresh the list."
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Column {
                    visible: root.passwordPromptVisible
                    width: parent.width
                    spacing: 4

                    Text {
                        width: parent.width
                        height: 16
                        text: "Password for: " + root.pendingDisplayName
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }

                    Row {
                        width: parent.width
                        height: 29
                        spacing: 5

                        TextField {
                            id: passwordField
                            width: parent.width - 112
                            height: parent.height
                            text: root.passwordInput
                            onTextChanged: root.passwordInput = text
                            placeholderText: "Wi-Fi password"
                            echoMode: TextInput.Password
                            selectByMouse: true
                            focus: root.visible && root.passwordPromptVisible
                            color: root.foregroundColor
                            placeholderTextColor: "#777777"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            leftPadding: 9
                            rightPadding: 9
                            background: Rectangle {
                                color: "#090909"
                                radius: 0
                                border.width: 1
                                border.color: "#414141"
                            }
                            Keys.onReturnPressed: root.submitPassword()
                        }

                        Rectangle {
                            width: 51
                            height: parent.height
                            radius: 0
                            color: cancelPasswordMouse.containsMouse ? "#202020" : "#0c0c0c"
                            border.width: 1
                            border.color: "#373737"
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
                            }
                            MouseArea {
                                id: cancelPasswordMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.passwordInput = "";
                                    root.passwordPromptVisible = false;
                                }
                            }
                        }

                        Rectangle {
                            width: 51
                            height: parent.height
                            radius: 0
                            color: connectPasswordMouse.containsMouse ? "#202020" : "#0c0c0c"
                            border.width: 1
                            border.color: "#373737"
                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
                            }
                            MouseArea {
                                id: connectPasswordMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submitPassword()
                            }
                        }
                    }
                }
            }

            Column {
                id: ethernetPage
                visible: root.activeTab === "ethernet"
                width: parent.width
                spacing: 7

                Row {
                    width: parent.width
                    height: 21
                    spacing: 7

                    Text {
                        text: "ETHERNET"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.ethernetStateLabel()
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: parent.width - 100
                    }
                }

                Column {
                    width: parent.width
                    spacing: 3

                    Text {
                        width: parent.width
                        height: 16
                        text: root.ethernetDevice ? "Interface: " + root.ethernetDevice : "Interface: not detected"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        height: 16
                        text: "IPv4: " + (root.ethernetIp || "unavailable")
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 112
                    height: 28
                    radius: 0
                    color: ethernetToggleMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                    border.width: 1
                    border.color: "#373737"
                    opacity: root.busy || root.statusLoading || root.scanLoading || !root.ethernetDevice ? 0.5 : 1

                    Text {
                        anchors.centerIn: parent
                        text: root.ethernetConnected() ? "Disconnect" : "Enable connection"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }

                    MouseArea {
                        id: ethernetToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.networkManagerAvailable && !!root.ethernetDevice && !root.busy && !root.statusLoading && !root.scanLoading
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleEthernet()
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
                height: 24

                Text {
                    anchors.fill: parent
                    text: root.errorMessage.length > 0
                        ? root.errorMessage
                        : (root.statusMessage.length > 0 ? root.statusMessage : root.connectivityLabel())
                    color: root.errorMessage.length > 0 ? "#d4d4d4" : root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }
    }
}
