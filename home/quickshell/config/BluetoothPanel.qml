import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null


    property string activeTab: "paired"
    property string selectedAdapterId: ""
    property string statusMessage: ""
    property string errorMessage: ""

    property bool busy: false
    property string busyAddress: ""
    property string busyAction: ""
    property string connectionCommandStage: ""
    property bool pairCommandStarted: false
    property double operationStartedAt: 0
    property double connectionObservedAt: 0
    property bool connectionWasObserved: false

    property bool powerPending: false
    property bool powerTargetEnabled: false
    property double powerStartedAt: 0

    property bool scanOwnedByPanel: false
    property string confirmForgetAddress: ""

    readonly property var adapterList: Bluetooth.adapters.values
    readonly property var activeAdapter: {
        const adapters = root.adapterList;
        if (!adapters || adapters.length === 0)
            return null;

        if (root.selectedAdapterId.length > 0) {
            for (let i = 0; i < adapters.length; i++) {
                if (adapters[i] && adapters[i].adapterId === root.selectedAdapterId)
                    return adapters[i];
            }
        }

        const defaultAdapter = Bluetooth.defaultAdapter;
        if (defaultAdapter) {
            for (let j = 0; j < adapters.length; j++) {
                if (adapters[j] === defaultAdapter)
                    return defaultAdapter;
            }
        }

        return adapters[0];
    }

    readonly property string adapterStatus: currentAdapterStatus()
    readonly property var pairedDevices: devicesForTab(true)
    readonly property var availableDevices: devicesForTab(false)

    width: 410 + Theme.popupPadX * 2
    height: 430 + Theme.popupPadY
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
        confirmForgetAddress = "";
        visible = true;
    }

    // PopupWindow can hide itself on an outside click, so cleanup belongs to the
    // visibility transition and must run for both automatic and programmatic closes.
    onVisibleChanged: {
        if (!root.visible) {
            root.confirmForgetAddress = "";
            if (root.scanOwnedByPanel) {
                if (root.activeAdapter && root.activeAdapter.discovering)
                    root.activeAdapter.discovering = false;
                root.scanOwnedByPanel = false;
            }
            scanTimeout.stop();
            scanStartTimeout.stop();
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

    function currentAdapterStatus() {
        if (!root.activeAdapter)
            return "UNAVAILABLE";

        const stateName = String(BluetoothAdapterState.toString(root.activeAdapter.state)).toLowerCase();
        if (stateName.indexOf("blocked") >= 0)
            return "UNAVAILABLE";
        if (stateName.indexOf("enabling") >= 0 || stateName.indexOf("disabling") >= 0)
            return "WORKING";

        return root.activeAdapter.enabled ? "ON" : "OFF";
    }

    function normalizedDeviceName(device) {
        return root.deviceName(device).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function hasKnownDeviceWithSameName(device, source) {
        const candidateName = root.normalizedDeviceName(device);
        if (!candidateName)
            return false;

        for (let i = 0; i < source.length; i++) {
            const other = source[i];
            if (!other || other.address === device.address)
                continue;

            const otherName = root.normalizedDeviceName(other);
            const known = !!(other.paired || other.bonded || other.connected);
            if (known && otherName === candidateName)
                return true;
        }
        return false;
    }

    function devicesForTab(pairedOnly) {
        const adapter = root.activeAdapter;
        if (!adapter || !adapter.devices)
            return [];

        const source = adapter.devices.values || [];
        const result = [];
        for (let i = 0; i < source.length; i++) {
            const device = source[i];
            if (!device)
                continue;

            const isPaired = !!(device.paired || device.bonded);
            if (pairedOnly) {
                if (isPaired)
                    result.push(device);
            } else if (!isPaired && !root.hasKnownDeviceWithSameName(device, source)) {
                // Some headsets expose a separate BLE/app advertisement with the same name.
                // Do not offer that second, often unpairable entry when the audio device is
                // already paired, bonded, or connected under another Bluetooth address.
                result.push(device);
            }
        }

        result.sort(function(a, b) {
            if (pairedOnly && !!a.connected !== !!b.connected)
                return a.connected ? -1 : 1;
            return root.deviceName(a).localeCompare(root.deviceName(b));
        });
        return result;
    }

    function deviceName(device) {
        if (!device)
            return "Unknown device";
        return String(device.name || device.deviceName || "Unknown device");
    }

    function deviceTypeLabel(device) {
        const icon = device && device.icon ? String(device.icon).toLowerCase() : "";
        if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0
                || icon.indexOf("audio") >= 0 || icon.indexOf("speaker") >= 0)
            return "AUDIO";
        if (icon.indexOf("keyboard") >= 0)
            return "KEYBOARD";
        if (icon.indexOf("mouse") >= 0 || icon.indexOf("touchpad") >= 0)
            return "MOUSE";
        if (icon.indexOf("game") >= 0 || icon.indexOf("joystick") >= 0 || icon.indexOf("controller") >= 0)
            return "CONTROLLER";
        if (icon.indexOf("phone") >= 0)
            return "PHONE";
        if (icon.indexOf("computer") >= 0 || icon.indexOf("laptop") >= 0)
            return "COMPUTER";
        return "BLUETOOTH DEVICE";
    }

    function deviceGlyph(device) {
        const type = root.deviceTypeLabel(device);
        if (type === "AUDIO")
            return "󰋋";
        if (type === "KEYBOARD")
            return "󰌌";
        if (type === "MOUSE")
            return "󰍽";
        if (type === "CONTROLLER")
            return "󰊴";
        if (type === "PHONE")
            return "󰄜";
        if (type === "COMPUTER")
            return "󰍹";
        return "󰂯";
    }

    function findDevice(address) {
        if (!root.activeAdapter || !root.activeAdapter.devices)
            return null;

        const devices = root.activeAdapter.devices.values || [];
        for (let i = 0; i < devices.length; i++) {
            if (devices[i] && devices[i].address === address)
                return devices[i];
        }
        return null;
    }

    function handlePairCommandOutput(data) {
        const line = String(data || "").trim();
        if (!line || !root.busy || root.busyAction !== "pair")
            return;

        const lower = line.toLowerCase();
        if (!root.pairCommandStarted &&
                (lower.indexOf("default agent request successful") >= 0
                    || lower.indexOf("default agent") >= 0 && lower.indexOf("successful") >= 0)) {
            root.pairCommandStarted = true;
            pairAgentFallback.stop();
            pairingCommand.write("pair " + root.busyAddress + "\n");
            return;
        }

        const isPairFailure = lower.indexOf("failed to pair") >= 0
            || lower.indexOf("authentication failed") >= 0
            || lower.indexOf("no agent available") >= 0
            || lower.indexOf("org.bluez.error") >= 0;
        if (root.pairCommandStarted && isPairFailure)
            root.finishDeviceAction(false, "Pairing failed: " + line.slice(0, 150));
    }

    function switchAdapter() {
        if (root.adapterList.length < 2 || root.busy || root.powerPending)
            return;

        if (root.scanOwnedByPanel) {
            if (root.activeAdapter && root.activeAdapter.discovering)
                root.activeAdapter.discovering = false;
            root.scanOwnedByPanel = false;
            scanTimeout.stop();
            scanStartTimeout.stop();
        }

        let currentIndex = -1;
        for (let i = 0; i < root.adapterList.length; i++) {
            if (root.adapterList[i] === root.activeAdapter) {
                currentIndex = i;
                break;
            }
        }
        const nextIndex = (currentIndex + 1) % root.adapterList.length;
        root.selectedAdapterId = root.adapterList[nextIndex].adapterId;
        root.confirmForgetAddress = "";
        root.statusMessage = "Using adapter " + root.adapterList[nextIndex].adapterId + ".";
        root.errorMessage = "";
    }

    function togglePower() {
        if (!root.activeAdapter || root.powerPending || root.busy)
            return;

        root.errorMessage = "";
        root.confirmForgetAddress = "";
        root.powerTargetEnabled = !root.activeAdapter.enabled;
        root.powerStartedAt = Date.now();
        root.powerPending = true;
        root.statusMessage = root.powerTargetEnabled ? "Enabling Bluetooth..." : "Disabling Bluetooth...";

        if (root.scanOwnedByPanel) {
            if (root.activeAdapter && root.activeAdapter.discovering)
                root.activeAdapter.discovering = false;
            root.scanOwnedByPanel = false;
            scanTimeout.stop();
            scanStartTimeout.stop();
        }

        try {
            root.activeAdapter.enabled = root.powerTargetEnabled;
        } catch (error) {
            root.powerPending = false;
            root.errorMessage = "Could not change Bluetooth power. Check BlueZ and permissions.";
            root.statusMessage = "";
        }
    }

    function checkPowerOperation() {
        if (!root.powerPending)
            return;

        if (!root.activeAdapter) {
            root.powerPending = false;
            root.errorMessage = "Bluetooth adapter is no longer available.";
            root.statusMessage = "";
            return;
        }

        if (root.activeAdapter.enabled === root.powerTargetEnabled
                && root.adapterStatus !== "WORKING") {
            root.powerPending = false;
            root.statusMessage = root.powerTargetEnabled ? "Bluetooth enabled." : "Bluetooth disabled.";
            return;
        }

        if (Date.now() - root.powerStartedAt > 10000) {
            root.powerPending = false;
            root.errorMessage = "Bluetooth power change timed out. Check BlueZ and permissions.";
            root.statusMessage = "";
        }
    }

    function startScan() {
        if (!root.activeAdapter || !root.activeAdapter.enabled || root.powerPending || root.busy)
            return;

        root.errorMessage = "";
        root.confirmForgetAddress = "";

        if (root.activeAdapter.discovering) {
            root.statusMessage = "A Bluetooth scan is already running.";
            return;
        }

        try {
            root.scanOwnedByPanel = true;
            root.activeAdapter.discovering = true;
            root.statusMessage = "Scanning for Bluetooth devices...";
            scanStartTimeout.restart();
            scanTimeout.restart();
        } catch (error) {
            root.scanOwnedByPanel = false;
            root.errorMessage = "Could not start scanning. Check the BlueZ service and permissions.";
            root.statusMessage = "";
        }
    }

    function confirmScanStarted() {
        if (root.scanOwnedByPanel && root.activeAdapter && !root.activeAdapter.discovering) {
            root.scanOwnedByPanel = false;
            scanTimeout.stop();
            root.errorMessage = "Could not start scanning. Check the BlueZ service and permissions.";
            root.statusMessage = "";
        }
    }

    function finishScan() {
        if (!root.scanOwnedByPanel)
            return;

        if (root.activeAdapter && root.activeAdapter.discovering)
            root.activeAdapter.discovering = false;

        root.scanOwnedByPanel = false;
        scanStartTimeout.stop();
        root.statusMessage = "Scan complete.";
    }

    function runDeviceAction(device, action) {
        if (!device || root.busy || root.powerPending)
            return;
        if (!root.activeAdapter || (!root.activeAdapter.enabled && action !== "forget")) {
            root.errorMessage = "Enable Bluetooth before managing this device.";
            return;
        }

        root.errorMessage = "";
        root.confirmForgetAddress = "";
        root.busy = true;
        root.busyAddress = device.address;
        root.busyAction = action;
        root.operationStartedAt = Date.now();
        root.connectionObservedAt = 0;
        root.connectionWasObserved = false;

        if (action === "connect" && !device.paired && !device.bonded) {
            root.busy = false;
            root.busyAddress = "";
            root.busyAction = "";
            root.errorMessage = "Device is not paired. Use PAIR first.";
            root.statusMessage = "";
            root.activeTab = "available";
            return;
        }

        if (action === "connect")
            root.statusMessage = "Connecting to " + root.deviceName(device) + "...";
        else if (action === "disconnect")
            root.statusMessage = "Disconnecting " + root.deviceName(device) + "...";
        else if (action === "pair")
            root.statusMessage = "Pairing " + root.deviceName(device) + "...";
        else if (action === "forget")
            root.statusMessage = "Removing " + root.deviceName(device) + "...";

        try {
            if (action === "connect") {
                // Use BlueZ's own CLI for connection attempts so failures are reported
                // consistently instead of silently waiting on the QML wrapper.
                if (device.blocked)
                    device.blocked = false;
                device.trusted = true;
                root.connectionCommandStage = "trust";
                connectionCommand.exec([
                    "/run/current-system/sw/bin/bluetoothctl",
                    "trust",
                    device.address
                ]);
            } else if (action === "disconnect") {
                device.disconnect();
            } else if (action === "pair") {
                // Quickshell's Bluetooth API does not provide an agent for pairing
                // flows that require one. Use BlueZ's bluetoothctl with a Just Works
                // agent for devices such as headphones, then verify pairing is stable.
                if (device.blocked)
                    device.blocked = false;
                root.pairCommandStarted = false;
                pairingCommand.exec([
                    "/run/current-system/sw/bin/bluetoothctl",
                    "--agent",
                    "NoInputNoOutput"
                ]);
            } else if (action === "forget") {
                device.forget();
            }
        } catch (error) {
            root.connectionCommandStage = "";
            root.finishDeviceAction(false, "Bluetooth operation failed. Check the BlueZ service and permissions.");
        }
    }

    function checkDeviceOperation() {
        if (!root.busy)
            return;

        const device = root.findDevice(root.busyAddress);
        if (root.busyAction === "forget") {
            if (!device || (!device.paired && !device.bonded)) {
                root.finishDeviceAction(true, "Device forgotten.");
                return;
            }
        } else if (!device) {
            root.finishDeviceAction(false, "Device disappeared during the operation.");
            return;
        } else if (root.busyAction === "connect") {
            if (device.connected) {
                if (root.connectionObservedAt === 0) {
                    root.connectionObservedAt = Date.now();
                    root.connectionWasObserved = true;
                }
                // BlueZ may briefly report connected before an LE link drops (HCI 0x3e).
                // Only report success after the connection remains stable for 2 seconds.
                if (Date.now() - root.connectionObservedAt >= 2000) {
                    root.finishDeviceAction(true, "Device connected.");
                    return;
                }
            } else if (root.connectionWasObserved) {
                root.finishDeviceAction(false,
                    "Connection dropped before it stabilized. Pair the device and try again nearby.");
                return;
            }
        } else if (root.busyAction === "disconnect" && !device.connected) {
            root.finishDeviceAction(true, "Device disconnected.");
            return;
        } else if (root.busyAction === "pair") {
            if (device.paired || device.bonded) {
                if (root.connectionObservedAt === 0)
                    root.connectionObservedAt = Date.now();

                // Do not switch tabs on a transient Paired=true update. BlueZ can
                // roll back a failed pairing shortly after the first property change.
                if (Date.now() - root.connectionObservedAt >= 2000) {
                    root.activeTab = "paired";
                    root.finishDeviceAction(true, "Device paired.");
                    return;
                }
            } else {
                root.connectionObservedAt = 0;
                if (!pairingCommand.running && root.pairCommandStarted
                        && Date.now() - root.operationStartedAt > 3000) {
                    root.finishDeviceAction(false,
                        "Pairing failed. Keep the QCY-T13 in pairing mode and try again nearby.");
                    return;
                }
            }
        }

        const timeout = root.busyAction === "pair" ? 45000 : 20000;
        if (Date.now() - root.operationStartedAt > timeout) {
            if (root.busyAction === "pair" && device && device.pairing) {
                try {
                    device.cancelPair();
                } catch (error) {
                }
            }

            if (root.busyAction === "pair" && pairingCommand.running)
                pairingCommand.write("quit\n");

            if (root.busyAction === "pair")
                root.finishDeviceAction(false, "Pairing timed out. An external Bluetooth agent may be required for PIN or passkey requests.");
            else if (root.busyAction === "forget")
                root.finishDeviceAction(false, "Could not remove pairing. Check the BlueZ service and permissions.");
            else
                root.finishDeviceAction(false, "The device operation timed out. Check that the device is available.");
        }
    }

    function finishDeviceAction(success, message) {
        if (root.busyAction === "pair" && pairingCommand.running)
            pairingCommand.write("quit\n");

        root.busy = false;
        root.busyAddress = "";
        root.busyAction = "";
        root.connectionCommandStage = "";
        root.pairCommandStarted = false;
        root.connectionObservedAt = 0;
        root.connectionWasObserved = false;
        if (success) {
            root.errorMessage = "";
            root.statusMessage = message;
            root.confirmForgetAddress = "";
        } else {
            root.errorMessage = message;
            root.statusMessage = "";
        }
    }

    function cancelPairing(device) {
        if (!device)
            return;

        try {
            device.cancelPair();
        } catch (error) {
        }

        if (root.busy && root.busyAddress === device.address && root.busyAction === "pair") {
            if (pairingCommand.running)
                pairingCommand.write("quit\n");
            root.finishDeviceAction(true, "Pairing cancellation requested.");
        }
        else
            root.statusMessage = "Pairing cancellation requested.";
    }

    function requestForget(device) {
        if (!device || root.busy || root.powerPending)
            return;
        root.errorMessage = "";
        root.confirmForgetAddress = device.address;
        root.statusMessage = "";
    }

    Connections {
        target: root.activeAdapter
        ignoreUnknownSignals: true

        function onDiscoveringChanged() {
            if (root.scanOwnedByPanel && root.activeAdapter && !root.activeAdapter.discovering) {
                root.scanOwnedByPanel = false;
                scanTimeout.stop();
                scanStartTimeout.stop();
                if (root.statusMessage === "Scanning for Bluetooth devices...")
                    root.statusMessage = "Scan complete.";
            }
        }

        function onEnabledChanged() {
            if (root.activeAdapter && !root.activeAdapter.enabled && root.scanOwnedByPanel) {
                root.scanOwnedByPanel = false;
                scanTimeout.stop();
                scanStartTimeout.stop();
                root.statusMessage = "Bluetooth disabled.";
            }
        }
    }

    Process {
        id: pairingCommand
        command: []
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.handlePairCommandOutput(data)
        }
        stderr: SplitParser {
            onRead: data => root.handlePairCommandOutput(data)
        }

        onStarted: {
            pairingCommand.write("default-agent\n");
            pairAgentFallback.restart();
        }

        onExited: (exitCode, exitStatus) => {
            pairAgentFallback.stop();
            if (!root.busy || root.busyAction !== "pair")
                return;

            const device = root.findDevice(root.busyAddress);
            if (device && (device.paired || device.bonded)) {
                // Let the watchdog confirm the paired state remains stable.
                return;
            }

            root.finishDeviceAction(false,
                "Pairing command exited before the device was paired. Keep it in pairing mode and try again.");
        }
    }

    Timer {
        id: pairAgentFallback
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.busy && root.busyAction === "pair"
                    && !root.pairCommandStarted && pairingCommand.running) {
                root.pairCommandStarted = true;
                pairingCommand.write("pair " + root.busyAddress + "\n");
            }
        }
    }

    Process {
        id: connectionCommand
        command: []

        onExited: (exitCode, exitStatus) => {
            if (!root.busy)
                return;

            if (root.connectionCommandStage === "trust") {
                // Trust may already be configured; always proceed to the connection.
                root.connectionCommandStage = "connect";
                connectionCommand.exec([
                    "/run/current-system/sw/bin/bluetoothctl",
                    "connect",
                    root.busyAddress
                ]);
                return;
            }

            if (root.connectionCommandStage === "connect") {
                root.connectionCommandStage = "";
                if (exitCode !== 0) {
                    root.finishDeviceAction(false,
                        "Connection failed. Ensure the device is on, nearby, paired, and not connected to another host.");
                }
            }
        }
    }

    Timer {
        id: operationWatchdog
        interval: 250
        repeat: true
        running: root.busy
        onTriggered: root.checkDeviceOperation()
    }

    Timer {
        id: powerWatchdog
        interval: 250
        repeat: true
        running: root.powerPending
        onTriggered: root.checkPowerOperation()
    }

    Timer {
        id: scanTimeout
        interval: 15000
        repeat: false
        onTriggered: root.finishScan()
    }

    Timer {
        id: scanStartTimeout
        interval: 2000
        repeat: false
        onTriggered: root.confirmScanStarted()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    // Device type names double as comparison keys above, so only their display is softened.
    function prettyType(device) {
        const type = root.deviceTypeLabel(device);
        return type.charAt(0) + type.slice(1).toLowerCase();
    }

    readonly property bool adapterOn: !!root.activeAdapter && root.activeAdapter.enabled

    PanelSurface {
        id: outerBorder
        window: root
        accent: Theme.iris

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 10

            PanelHeader {
                glyph: root.adapterOn ? Theme.icons.bluetooth : Theme.icons.bluetoothOff
                accent: Theme.iris
                title: "Bluetooth"
                subtitle: root.errorMessage.length > 0
                    ? root.errorMessage
                    : (root.statusMessage.length > 0
                        ? root.statusMessage
                        : (root.adapterStatus === "UNAVAILABLE"
                            ? "Bluetooth service unavailable."
                            : (root.adapterStatus === "OFF"
                                ? "Bluetooth is disabled."
                                : "Bluetooth ready.")))

                SoftSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.powerPending ? root.powerTargetEnabled : root.adapterOn
                    enabled: !!root.activeAdapter && !root.busy && !root.powerPending
                    onClicked: root.togglePower()
                }
            }

            Rectangle {
                visible: root.adapterList.length > 1
                width: parent.width
                height: 40
                radius: 14
                color: Theme.surface

                UiText {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: switchAdapterButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.activeAdapter
                        ? root.activeAdapter.adapterId + " — " + root.activeAdapter.name
                        : "Adapter unavailable"
                    color: Theme.subtle
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                SoftButton {
                    id: switchAdapterButton
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Switch"
                    glyph: Theme.icons.swap
                    fontSize: 11
                    enabled: !root.busy && !root.powerPending
                    onClicked: root.switchAdapter()
                }
            }

            SegmentTabs {
                id: tabBar
                current: root.activeTab
                tabs: [
                    { key: "paired", label: "Paired" },
                    { key: "available", label: "Available" }
                ]
                onPicked: function(key) {
                    root.activeTab = key;
                    root.confirmForgetAddress = "";
                }
            }

            Item {
                visible: root.activeTab === "available"
                width: parent.width
                height: 32

                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.activeAdapter && root.activeAdapter.discovering
                        ? "Scanning…"
                        : "Available devices"
                    color: root.activeAdapter && root.activeAdapter.discovering ? Theme.iris : Theme.subtle
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                SoftButton {
                    anchors.right: parent.right
                    label: "Scan"
                    glyph: Theme.icons.refresh
                    fontSize: 11
                    enabled: !!root.activeAdapter && root.activeAdapter.enabled
                        && !root.activeAdapter.discovering && !root.busy && !root.powerPending
                    onClicked: root.startScan()
                }
            }

            Item {
                id: listContainer
                width: parent.width
                height: parent.height - 40 - tabBar.height - parent.spacing * 2
                    - (root.adapterList.length > 1 ? 40 + parent.spacing : 0)
                    - (root.activeTab === "available" ? 32 + parent.spacing : 0)

                ListView {
                    id: pairedList
                    anchors.fill: parent
                    visible: root.activeTab === "paired"
                    clip: true
                    spacing: 6
                    model: root.pairedDevices

                    delegate: Rectangle {
                        id: pairedDeviceRow
                        required property var modelData
                        readonly property var device: modelData
                        readonly property bool isBusy: root.busy && root.busyAddress === device.address
                        readonly property bool confirmingForget: root.confirmForgetAddress === device.address

                        width: ListView.view.width
                        height: 58
                        radius: Theme.radiusTile
                        color: device.connected ? Theme.tint(Theme.iris, 0.14) : Theme.surface

                        Rectangle {
                            id: pairedBadge
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: pairedDeviceRow.device.connected ? Theme.iris : Theme.raised

                            Icon {
                                anchors.centerIn: parent
                                text: root.deviceGlyph(pairedDeviceRow.device)
                                color: pairedDeviceRow.device.connected ? Theme.onAccent : Theme.subtle
                                font.pixelSize: 18
                            }
                        }

                        Column {
                            anchors.left: pairedBadge.right
                            anchors.leftMargin: 10
                            anchors.right: pairedActions.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            UiText {
                                width: parent.width
                                text: root.deviceName(pairedDeviceRow.device)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            UiText {
                                width: parent.width
                                text: {
                                    const device = pairedDeviceRow.device;
                                    let detail = device.connected ? "Connected" : "Paired";
                                    if (device.batteryAvailable)
                                        detail += "  ·  " + Math.round(device.battery * 100) + "%";
                                    if (pairedDeviceRow.isBusy) {
                                        if (root.busyAction === "connect")
                                            detail = "Connecting…";
                                        else if (root.busyAction === "disconnect")
                                            detail = "Disconnecting…";
                                        else if (root.busyAction === "forget")
                                            detail = "Removing…";
                                    }
                                    return detail;
                                }
                                color: pairedDeviceRow.device.connected ? Theme.iris : Theme.subtle
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: pairedActions
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            SoftButton {
                                visible: !pairedDeviceRow.confirmingForget
                                label: pairedDeviceRow.device.connected ? "Disconnect" : "Connect"
                                variant: pairedDeviceRow.device.connected ? "tonal" : "accent"
                                fontSize: 11
                                enabled: !root.busy && !root.powerPending
                                    && !!root.activeAdapter && root.activeAdapter.enabled
                                onClicked: root.runDeviceAction(
                                    pairedDeviceRow.device,
                                    pairedDeviceRow.device.connected ? "disconnect" : "connect"
                                )
                            }

                            SoftButton {
                                visible: !pairedDeviceRow.confirmingForget
                                glyph: Theme.icons.trash
                                variant: "ghost"
                                enabled: !root.busy && !root.powerPending && !!root.activeAdapter
                                onClicked: root.requestForget(pairedDeviceRow.device)
                            }

                            SoftButton {
                                visible: pairedDeviceRow.confirmingForget
                                label: "Forget"
                                variant: "danger"
                                fontSize: 11
                                enabled: !root.busy && !root.powerPending && !!root.activeAdapter
                                onClicked: root.runDeviceAction(pairedDeviceRow.device, "forget")
                            }

                            SoftButton {
                                visible: pairedDeviceRow.confirmingForget
                                label: "Cancel"
                                variant: "ghost"
                                fontSize: 11
                                onClicked: root.confirmForgetAddress = ""
                            }
                        }
                    }
                }

                ListView {
                    id: availableList
                    anchors.fill: parent
                    visible: root.activeTab === "available"
                    clip: true
                    spacing: 6
                    model: root.availableDevices

                    delegate: Rectangle {
                        id: availableDeviceRow
                        required property var modelData
                        readonly property var device: modelData
                        readonly property bool isPairing: device.pairing
                            || (root.busy && root.busyAddress === device.address && root.busyAction === "pair")

                        width: ListView.view.width
                        height: 58
                        radius: Theme.radiusTile
                        color: Theme.surface

                        Rectangle {
                            id: availableBadge
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.raised

                            Icon {
                                anchors.centerIn: parent
                                text: root.deviceGlyph(availableDeviceRow.device)
                                color: Theme.subtle
                                font.pixelSize: 18
                            }
                        }

                        Column {
                            anchors.left: availableBadge.right
                            anchors.leftMargin: 10
                            anchors.right: pairButton.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            UiText {
                                width: parent.width
                                text: root.deviceName(availableDeviceRow.device)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            UiText {
                                width: parent.width
                                text: availableDeviceRow.isPairing
                                    ? "Pairing…"
                                    : root.prettyType(availableDeviceRow.device)
                                color: Theme.subtle
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        SoftButton {
                            id: pairButton
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            label: availableDeviceRow.isPairing ? "Cancel" : "Pair"
                            variant: availableDeviceRow.isPairing ? "ghost" : "accent"
                            fontSize: 11
                            enabled: !root.powerPending
                                && !!root.activeAdapter && root.activeAdapter.enabled
                                && (!root.busy || (root.busyAction === "pair"
                                    && root.busyAddress === availableDeviceRow.device.address))
                            onClicked: {
                                if (availableDeviceRow.device.pairing
                                        || (root.busy && root.busyAction === "pair"
                                            && root.busyAddress === availableDeviceRow.device.address))
                                    root.cancelPairing(availableDeviceRow.device);
                                else
                                    root.runDeviceAction(availableDeviceRow.device, "pair");
                            }
                        }
                    }
                }

                UiText {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (!root.activeAdapter)
                            return "Bluetooth service or adapter unavailable.";
                        if (!root.activeAdapter.enabled)
                            return "Bluetooth is disabled.";
                        if (root.activeTab === "paired")
                            return root.pairedDevices.length === 0 ? "No paired devices." : "";
                        if (root.activeAdapter.discovering)
                            return "Scanning for devices…";
                        return root.availableDevices.length === 0 ? "No devices found." : "";
                    }
                    visible: root.activeTab === "paired"
                        ? root.pairedDevices.length === 0
                        : root.availableDevices.length === 0
                    color: Theme.subtle
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
