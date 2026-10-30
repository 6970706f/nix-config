import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// One received notification. It outlives the D-Bus object it mirrors, so the history can
// keep showing it after the sender closes it and across shell restarts.
QtObject {
    id: entry

    // Set by NotificationService; unique for the lifetime of the shell.
    property int key: 0

    // Null once the notification is closed: actions and raw images die with it.
    property var notification: null
    property int notificationId: 0

    property string appName: ""
    property string appIcon: ""
    property string image: ""
    property string summary: ""
    property string body: ""
    property int urgency: NotificationUrgency.Normal
    property real time: Date.now()
    property bool read: false
    property bool isTransient: false

    // Whether it is on screen as a pop-up, and whether the pointer is keeping it there.
    property bool popup: false
    property bool hovered: false

    property var actions: []
    property var defaultAction: null

    // Sender-provided lifetime in ms: -1 means unset and 0 means never expire.
    property real expireTimeout: -1

    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property string title: entry.summary || entry.appName || "Notification"
    readonly property string appLabel: entry.appName || "Notification"

    // StyledText would otherwise load any image the markup points at, even remote ones.
    readonly property string displayBody: entry.body.replace(/<img\b[^>]*>/gi, "").trim()

    // The server wraps icon names and paths as image://icon/..., which draws a placeholder
    // for anything missing, so those are resolved here instead.
    readonly property bool imageIsIcon: entry.image.startsWith("image://icon/")
    readonly property string iconName: entry.imageIsIcon ? entry.image.slice(13) : entry.appIcon
    readonly property bool hasPicture: entry.imageIsIcon
        ? entry.iconName.startsWith("/")
        : entry.image.length > 0
    readonly property string iconSource: {
        if (entry.image.length > 0 && !entry.imageIsIcon)
            return entry.image;
        if (entry.iconName.startsWith("/"))
            return "file://" + entry.iconName;
        if (entry.iconName.indexOf("://") !== -1)
            return entry.iconName;
        return entry.iconName.length > 0 ? Quickshell.iconPath(entry.iconName, true) : "";
    }

    readonly property int popupTimeout: {
        if (entry.critical || entry.expireTimeout === 0)
            return 0;
        if (entry.expireTimeout > 0)
            return entry.expireTimeout;
        return entry.urgency === NotificationUrgency.Low ? 4000 : 6000;
    }

    // Reasons a change matters to the service: state to save, or a new revision to show.
    signal modified()
    signal updated()
    signal popupEnded()

    onReadChanged: entry.modified()
    onPopupChanged: {
        if (!entry.popup)
            entry.popupEnded();
    }

    function attach(source) {
        entry.notification = source;
        entry.notificationId = source.id;
        entry.sync();
    }

    function sync() {
        const source = entry.notification;
        if (!source)
            return;

        entry.appName = source.appName;
        const desktopEntry = DesktopEntries.byId(source.desktopEntry)
            || DesktopEntries.heuristicLookup(source.appName);
        entry.appIcon = source.appIcon || (desktopEntry ? desktopEntry.icon : "");
        entry.image = source.image;
        entry.summary = source.summary;
        entry.body = source.body;
        entry.urgency = source.urgency;
        entry.isTransient = source.transient;
        entry.expireTimeout = source.expireTimeout;
        entry.actions = source.actions.filter(function(action) {
            return action.identifier !== "default";
        });
        entry.defaultAction = source.actions.find(function(action) {
            return action.identifier === "default";
        }) || null;
    }

    function revise() {
        if (!entry.notification)
            return;

        entry.sync();
        entry.time = Date.now();
        entry.read = false;
        entry.updated();
        if (popupTimer.running)
            popupTimer.restart();
    }

    readonly property Connections sourceConnections: Connections {
        target: entry.notification
        ignoreUnknownSignals: true

        // A replacement arrives as several property changes on the same object.
        function onSummaryChanged() { Qt.callLater(entry.revise); }
        function onBodyChanged() { Qt.callLater(entry.revise); }
        function onActionsChanged() { Qt.callLater(entry.revise); }
        function onImageChanged() { Qt.callLater(entry.sync); }
        function onUrgencyChanged() { Qt.callLater(entry.sync); }

        function onClosed(reason) {
            entry.notification = null;
            entry.actions = [];
            entry.defaultAction = null;
            // Pixel data served by the notification itself is gone; paths still resolve.
            if (entry.image.startsWith("image://") && !entry.image.startsWith("image://icon/"))
                entry.image = "";
            entry.popup = false;
            entry.modified();
        }
    }

    readonly property Timer popupTimer: Timer {
        interval: entry.popupTimeout
        running: entry.popup && !entry.hovered && entry.popupTimeout > 0
        onTriggered: {
            entry.popup = false;
            // Only an explicit lifetime ends the notification; otherwise its actions
            // stay usable from the notification center.
            if (entry.expireTimeout > 0 && entry.notification)
                entry.notification.expire();
        }
    }
}
