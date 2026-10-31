pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// Owns the org.freedesktop.Notifications name and the single notification list shared by
// every screen's pop-ups, bar indicator and notification center.
Singleton {
    id: root

    readonly property int historyLimit: 100
    readonly property int popupLimit: 4

    // Newest first.
    property var entries: []
    property bool centerOpen: false

    // Keeps everything but critical notifications from popping up; the history still fills.
    property bool doNotDisturb: false

    // Transient notifications only ever exist as pop-ups.
    readonly property var history: root.entries.filter(function(entry) {
        return !entry.isTransient;
    })
    readonly property var popups: root.entries.filter(function(entry) {
        return entry.popup;
    }).slice(0, root.popupLimit)
    readonly property int unreadCount: root.history.filter(function(entry) {
        return !entry.read;
    }).length

    property int nextKey: 1
    property bool stateReady: false

    signal centerToggleRequested(string screenName)
    signal actionInvoked()

    onDoNotDisturbChanged: {
        if (root.doNotDisturb) {
            root.entries.forEach(function(entry) {
                if (!entry.critical)
                    entry.popup = false;
            });
        }
        root.scheduleSave();
    }

    function createEntry(properties) {
        const entry = entryComponent.createObject(root, Object.assign({ key: root.nextKey }, properties));
        root.nextKey += 1;
        entry.modified.connect(root.scheduleSave);
        entry.updated.connect(function() {
            root.promote(entry);
        });
        entry.popupEnded.connect(function() {
            if (entry.isTransient)
                root.dismiss(entry);
        });
        return entry;
    }

    function receive(notification) {
        root.replaceSameTag(notification);

        const entry = root.createEntry({});
        entry.attach(notification);
        notification.tracked = true;

        root.entries = [entry].concat(root.entries);
        root.present(entry);
        root.trimHistory();
        root.scheduleSave();
    }

    // A transient notification that can't pop up has nowhere else to exist.
    function present(entry) {
        entry.popup = !root.centerOpen && (!root.doNotDisturb || entry.critical);
        if (entry.isTransient && !entry.popup)
            root.dismiss(entry);
    }

    // Volume and brightness scripts replace their previous notification through these hints.
    function stackTag(notification) {
        const hints = notification.hints;
        return hints["x-canonical-private-synchronous"] || hints["x-dunst-stack-tag"] || "";
    }

    function replaceSameTag(notification) {
        const tag = root.stackTag(notification);
        if (tag.length === 0)
            return;

        root.entries.filter(function(entry) {
            return entry.notification
                && entry.appName === notification.appName
                && root.stackTag(entry.notification) === tag;
        }).forEach(root.dismiss);
    }

    function trimHistory() {
        root.history.slice(root.historyLimit).forEach(root.dismiss);
    }

    function promote(entry) {
        root.entries = [entry].concat(root.entries.filter(function(candidate) {
            return candidate !== entry;
        }));
        root.present(entry);
        root.scheduleSave();
    }

    // Removes it from the history and closes it for the sender.
    function dismiss(entry) {
        if (root.entries.indexOf(entry) === -1)
            return;

        root.entries = root.entries.filter(function(candidate) {
            return candidate !== entry;
        });

        const notification = entry.notification;
        entry.popup = false;
        if (notification) {
            entry.notification = null;
            notification.dismiss();
        }

        // Delegates may still be animating this entry out.
        entry.destroy(Theme.normal * 4);
        root.scheduleSave();
    }

    function clearAll() {
        root.entries.slice().forEach(root.dismiss);
    }

    // Takes it off screen; it stays in the history with its actions available.
    function hidePopup(entry) {
        entry.read = true;
        entry.popup = false;
    }

    function markAllRead() {
        root.entries.forEach(function(entry) {
            entry.read = true;
        });
    }

    function invokeAction(entry, action) {
        entry.read = true;
        entry.popup = false;
        action.invoke();
        root.actionInvoked();
    }

    // Everything the center can show should not also cover it from above.
    function setCenterOpen(open) {
        root.centerOpen = open;
        if (open) {
            root.entries.forEach(function(entry) {
                entry.popup = false;
            });
        } else {
            root.markAllRead();
        }
    }

    function timeLabel(time) {
        const elapsed = Math.max(0, (clock.date.getTime() - time) / 60000);
        if (elapsed < 1)
            return "now";
        if (elapsed < 60)
            return Math.floor(elapsed) + "m";
        if (elapsed < 1440)
            return Math.floor(elapsed / 60) + "h";
        if (elapsed < 10080)
            return Math.floor(elapsed / 1440) + "d";
        return new Date(time).toLocaleDateString(Qt.locale("en_US"), "d MMM");
    }

    function scheduleSave() {
        if (root.stateReady)
            saveTimer.restart();
    }

    function saveState() {
        const saved = root.history.map(function(entry) {
            return {
                notificationId: entry.notificationId,
                appName: entry.appName,
                appIcon: entry.appIcon,
                // Raw pixel data is only reachable through the live notification.
                image: entry.image.startsWith("image://icon/") ? entry.image : "",
                summary: entry.summary,
                body: entry.body,
                urgency: entry.urgency,
                time: entry.time,
                read: entry.read
            };
        });

        try {
            stateFile.setText(JSON.stringify({
                version: 1,
                doNotDisturb: root.doNotDisturb,
                entries: saved
            }));
        } catch (error) {
            console.warn("Notifications: could not save history:", error);
        }
    }

    function restoreState() {
        let restored = [];
        try {
            const raw = stateFile.text();
            const state = raw && raw.trim().length > 0 ? JSON.parse(raw) : null;
            if (state)
                root.doNotDisturb = state.doNotDisturb === true;
            if (state && Array.isArray(state.entries))
                restored = state.entries.slice(0, root.historyLimit).map(root.createEntry);
        } catch (error) {
            console.warn("Notifications: could not read history:", error);
        }

        // Anything received while the file was loading is newer than the saved history.
        root.entries = root.entries.concat(restored);
        root.stateReady = true;
        root.adoptTracked();
    }

    // A shell reload keeps live notifications on the server but rebuilds this singleton,
    // so saved entries have to find their notification again to get their actions back.
    function adoptTracked() {
        if (!root.stateReady)
            return;

        server.trackedNotifications.values.forEach(function(notification) {
            const adopted = root.entries.some(function(entry) {
                return entry.notification === notification;
            });
            if (adopted)
                return;

            const saved = root.entries.find(function(entry) {
                return !entry.notification
                    && entry.notificationId === notification.id
                    && entry.summary === notification.summary;
            });

            if (saved) {
                saved.attach(notification);
            } else {
                const entry = root.createEntry({});
                entry.attach(notification);
                root.entries = [entry].concat(root.entries);
            }
        });
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: function(notification) {
            root.receive(notification);
        }
    }

    Connections {
        target: server.trackedNotifications

        function onValuesChanged() {
            root.adoptTracked();
        }
    }

    Component {
        id: entryComponent
        NotificationEntry {}
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveState()
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("notifications.json")
        printErrors: false
        watchChanges: false
        onLoaded: root.restoreState()
        onLoadFailed: root.restoreState()
        onSaveFailed: function(error) {
            console.warn("Notifications: history write failed:", error);
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            const monitor = Hyprland.focusedMonitor;
            root.centerToggleRequested(monitor ? monitor.name : "");
        }

        function clearAll(): void {
            root.clearAll();
        }

        function markAllRead(): void {
            root.markAllRead();
        }

        function toggleDoNotDisturb(): void {
            root.doNotDisturb = !root.doNotDisturb;
        }
    }
}
