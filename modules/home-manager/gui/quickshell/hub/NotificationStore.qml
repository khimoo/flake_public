import QtQuick
import Quickshell.Services.Notifications

Item {
    id: store

    property bool dnd: false
    property var history: []
    property var activePopups: []
    property int unreadCount: 0
    property int nextEntryId: 1

    readonly property int maxHistory: 100
    readonly property int popupDurationMs: 5000

    signal activated()

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: function(notification) {
            notification.tracked = true;
            var isCritical = (notification.urgency === NotificationUrgency.Critical);
            var now = new Date();
            var hh = String(now.getHours()).padStart(2, "0");
            var mm = String(now.getMinutes()).padStart(2, "0");

            var entry = {
                entryId: store.nextEntryId++,
                notifId: notification.id,
                appName: notification.appName || "通知",
                summary: notification.summary || "",
                body: notification.body || "",
                timeText: hh + ":" + mm,
                isCritical: isCritical,
                read: false,
                notification: notification,
                expiresAt: isCritical ? 0 : (Date.now() + store.popupDurationMs)
            };

            // 同じ notifId の置き換え通知（failure-notify の --replace-id 等）は既存項目を更新する。
            var nextHistory = [];
            var replaced = false;
            for (var i = 0; i < store.history.length; i++) {
                if (store.history[i].notifId === notification.id && notification.id > 0) {
                    nextHistory.push(entry);
                    replaced = true;
                } else {
                    nextHistory.push(store.history[i]);
                }
            }
            if (!replaced) {
                nextHistory.unshift(entry);
            }
            if (nextHistory.length > store.maxHistory) {
                nextHistory = nextHistory.slice(0, store.maxHistory);
            }
            store.history = nextHistory;
            store.recountUnread();

            if (!store.dnd || isCritical) {
                var nextPopups = [];
                var popupReplaced = false;
                for (var j = 0; j < store.activePopups.length; j++) {
                    if (store.activePopups[j].notifId === notification.id && notification.id > 0) {
                        nextPopups.push(entry);
                        popupReplaced = true;
                    } else {
                        nextPopups.push(store.activePopups[j]);
                    }
                }
                if (!popupReplaced) {
                    nextPopups.unshift(entry);
                }
                if (nextPopups.length > 4) {
                    nextPopups = nextPopups.slice(0, 4);
                }
                store.activePopups = nextPopups;
            }
        }
    }

    Timer {
        interval: 500
        running: store.activePopups.length > 0
        repeat: true
        onTriggered: {
            var now = Date.now();
            var remaining = [];
            var changed = false;
            for (var i = 0; i < store.activePopups.length; i++) {
                var p = store.activePopups[i];
                if (p.isCritical || p.expiresAt === 0 || p.expiresAt > now) {
                    remaining.push(p);
                } else {
                    changed = true;
                }
            }
            if (changed) {
                store.activePopups = remaining;
            }
        }
    }

    function recountUnread() {
        var c = 0;
        for (var i = 0; i < history.length; i++) {
            if (!history[i].read) c++;
        }
        unreadCount = c;
    }

    function markAllRead() {
        var next = [];
        for (var i = 0; i < history.length; i++) {
            var h = history[i];
            if (!h.read) {
                h = Object.assign({}, h, { read: true });
            }
            next.push(h);
        }
        history = next;
        unreadCount = 0;
    }

    function dismissPopup(entryId) {
        var next = [];
        for (var i = 0; i < activePopups.length; i++) {
            if (activePopups[i].entryId !== entryId) {
                next.push(activePopups[i]);
            }
        }
        activePopups = next;
    }

    function removeEntry(entryId) {
        dismissPopup(entryId);
        var next = [];
        for (var i = 0; i < history.length; i++) {
            var h = history[i];
            if (h.entryId === entryId) {
                if (h.notification) {
                    try { h.notification.dismiss(); } catch (e) {}
                }
            } else {
                next.push(h);
            }
        }
        history = next;
        recountUnread();
    }

    function clearAll() {
        for (var i = 0; i < history.length; i++) {
            if (history[i].notification) {
                try { history[i].notification.dismiss(); } catch (e) {}
            }
        }
        activePopups = [];
        history = [];
        unreadCount = 0;
    }

    function invokeDefault(entry) {
        if (!entry) return;
        dismissPopup(entry.entryId);
        if (entry.notification && entry.notification.actions) {
            var acts = entry.notification.actions;
            var target = null;
            for (var i = 0; i < acts.length; i++) {
                if (acts[i].identifier === "default") {
                    target = acts[i];
                    break;
                }
            }
            if (!target && acts.length > 0) {
                target = acts[0];
            }
            if (target) {
                try { target.invoke(); } catch (e) {}
            }
        }
        // 既読化
        var next = [];
        for (var j = 0; j < history.length; j++) {
            var h = history[j];
            if (h.entryId === entry.entryId && !h.read) {
                h = Object.assign({}, h, { read: true });
            }
            next.push(h);
        }
        history = next;
        recountUnread();
        activated();
    }
}
