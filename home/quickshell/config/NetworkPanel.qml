import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null


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

    width: 390 + Theme.popupPadX * 2
    height: (activeTab === "wifi" ? 466 : 300) + Theme.popupPadY
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

    function signalGlyph(signal) {
        if (signal >= 75)
            return Theme.icons.wifi4;
        if (signal >= 50)
            return Theme.icons.wifi3;
        if (signal >= 25)
            return Theme.icons.wifi2;
        return Theme.icons.wifi1;
    }

    readonly property bool controlsIdle: !root.busy && !root.statusLoading && !root.scanLoading

    PanelSurface {
        id: outerBorder
        window: root
        accent: Theme.foam

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 10

            PanelHeader {
                glyph: root.activeTab === "wifi" ? Theme.icons.wifi4 : Theme.icons.ethernet
                accent: Theme.foam
                title: "Network"
                subtitle: root.errorMessage.length > 0
                    ? "Needs attention"
                    : (root.statusLoading ? "Refreshing…" : (root.busy ? "Working…" : root.connectivityLabel()))
            }

            SegmentTabs {
                id: tabBar
                accent: Theme.foam
                current: root.activeTab
                tabs: [
                    { key: "wifi", label: "Wi-Fi" },
                    { key: "ethernet", label: "Ethernet" }
                ]
                onPicked: function(key) { root.activeTab = key; }
            }

            Column {
                id: wifiPage
                visible: root.activeTab === "wifi"
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 62
                    radius: 18
                    color: root.wifiConnected() ? Theme.tint(Theme.foam, 0.14) : Theme.surface

                    Icon {
                        id: wifiStateIcon
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wifiEnabled
                            ? root.signalGlyph(parseInt(root.wifiSignal, 10) || 0)
                            : Theme.icons.wifiOff
                        color: root.wifiConnected() ? Theme.foam : Theme.muted
                        font.pixelSize: 24
                    }

                    Column {
                        anchors.left: wifiStateIcon.right
                        anchors.leftMargin: 12
                        anchors.right: wifiSwitch.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        UiText {
                            width: parent.width
                            text: root.wifiConnected() ? root.currentWifiName() : "No Wi-Fi network connected"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        UiText {
                            width: parent.width
                            text: root.wifiStateLabel() + (root.wifiIp ? "  ·  " + root.wifiIp : "")
                            color: Theme.subtle
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    SoftSwitch {
                        id: wifiSwitch
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        accent: Theme.foam
                        checked: root.wifiEnabled
                        enabled: root.networkManagerAvailable && root.controlsIdle
                        onClicked: root.setWifiEnabled(!root.wifiEnabled)
                    }
                }

                Item {
                    width: parent.width
                    height: 32

                    UiText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Networks"
                        color: Theme.subtle
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 6

                        SoftButton {
                            visible: root.wifiConnected()
                            label: "Disconnect"
                            fontSize: 11
                            enabled: root.networkManagerAvailable && root.controlsIdle
                            onClicked: root.disconnectWifi()
                        }

                        SoftButton {
                            label: root.scanLoading ? "Scanning…" : "Refresh"
                            glyph: Theme.icons.refresh
                            fontSize: 11
                            enabled: root.networkManagerAvailable && root.wifiEnabled && root.controlsIdle
                            onClicked: root.refreshNetworks(true)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.passwordPromptVisible ? 112 : 192

                    ListView {
                        id: wifiList
                        anchors.fill: parent
                        clip: true
                        spacing: 2
                        model: root.wifiNetworks
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: networkRow
                            required property var modelData
                            width: wifiList.width
                            height: 38
                            radius: 13
                            color: modelData.inUse
                                ? Theme.tint(Theme.foam, 0.14)
                                : (networkRowMouse.containsMouse ? Theme.surface : "transparent")

                            Behavior on color {
                                ColorAnimation { duration: Theme.fast }
                            }

                            Icon {
                                id: networkSignalIcon
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                text: root.signalGlyph(networkRow.modelData.signal)
                                color: networkRow.modelData.inUse ? Theme.foam : Theme.subtle
                                font.pixelSize: 15
                            }

                            UiText {
                                anchors.left: networkSignalIcon.right
                                anchors.leftMargin: 10
                                anchors.right: networkMeta.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: networkRow.modelData.ssid
                                font.pixelSize: 12
                                font.weight: networkRow.modelData.inUse ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Row {
                                id: networkMeta
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                UiText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: networkRow.modelData.signal > 0 ? networkRow.modelData.signal + "%" : "--"
                                    color: Theme.subtle
                                    font.pixelSize: 11
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: networkRow.modelData.security !== "--"
                                    text: Theme.icons.lock
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: networkRow.modelData.inUse
                                    text: Theme.icons.check
                                    color: Theme.foam
                                    font.pixelSize: 14
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

                    UiText {
                        anchors.centerIn: parent
                        visible: root.wifiNetworks.length === 0
                            && (root.scanLoading || (root.wifiEnabled && root.wifiDevice.length > 0))
                        text: root.scanLoading ? "Scanning for available networks…" : "No networks found. Refresh the list."
                        color: Theme.subtle
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    visible: root.passwordPromptVisible
                    width: parent.width
                    height: 76
                    radius: Theme.radiusTile
                    color: Theme.surface

                    UiText {
                        x: 12
                        y: 8
                        width: parent.width - 24
                        text: "Password for " + root.pendingDisplayName
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        height: 32
                        spacing: 5

                        TextField {
                            id: passwordField
                            width: parent.width - cancelPasswordButton.width - connectPasswordButton.width - parent.spacing * 2
                            height: parent.height
                            text: root.passwordInput
                            onTextChanged: root.passwordInput = text
                            placeholderText: "Wi-Fi password"
                            echoMode: TextInput.Password
                            selectByMouse: true
                            focus: root.visible && root.passwordPromptVisible
                            color: Theme.text
                            placeholderTextColor: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            leftPadding: 12
                            rightPadding: 12
                            background: Rectangle {
                                color: Theme.base
                                radius: height / 2
                                border.width: 1
                                border.color: passwordField.activeFocus ? Theme.foam : Theme.stroke
                            }
                            Keys.onReturnPressed: root.submitPassword()
                        }

                        SoftButton {
                            id: cancelPasswordButton
                            label: "Cancel"
                            fontSize: 11
                            variant: "ghost"
                            onClicked: {
                                root.passwordInput = "";
                                root.passwordPromptVisible = false;
                            }
                        }

                        SoftButton {
                            id: connectPasswordButton
                            label: "Connect"
                            fontSize: 11
                            variant: "accent"
                            accent: Theme.foam
                            enabled: !root.busy
                            onClicked: root.submitPassword()
                        }
                    }
                }
            }

            Column {
                id: ethernetPage
                visible: root.activeTab === "ethernet"
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 62
                    radius: 18
                    color: root.ethernetConnected() ? Theme.tint(Theme.foam, 0.14) : Theme.surface

                    Icon {
                        id: ethernetStateIcon
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icons.ethernet
                        color: root.ethernetConnected() ? Theme.foam : Theme.muted
                        font.pixelSize: 24
                    }

                    Column {
                        anchors.left: ethernetStateIcon.right
                        anchors.leftMargin: 12
                        anchors.right: ethernetToggleButton.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        UiText {
                            width: parent.width
                            text: root.ethernetStateLabel()
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        UiText {
                            width: parent.width
                            text: root.ethernetDevice ? "Interface: " + root.ethernetDevice : "Interface: not detected"
                            color: Theme.subtle
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    SoftButton {
                        id: ethernetToggleButton
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        label: root.ethernetConnected() ? "Disconnect" : "Enable"
                        fontSize: 11
                        enabled: root.networkManagerAvailable && !!root.ethernetDevice && root.controlsIdle
                        onClicked: root.toggleEthernet()
                    }
                }

                StatTile {
                    width: parent.width
                    label: "IPv4 address"
                    value: root.ethernetIp || "unavailable"
                }
            }

            UiText {
                width: parent.width
                height: 18
                text: root.errorMessage.length > 0
                    ? root.errorMessage
                    : (root.statusMessage.length > 0 ? root.statusMessage : root.connectivityLabel())
                color: root.errorMessage.length > 0 ? Theme.love : Theme.subtle
                font.pixelSize: 11
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
    }
}
