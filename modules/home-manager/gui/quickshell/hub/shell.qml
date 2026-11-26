//@ pragma UseQApplication
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    NotificationStore {
        id: notifStore
    }

    NotificationPopups {
        store: notifStore
    }

    HubWindow {
        id: hub
        store: notifStore
    }

    IpcHandler {
        target: "hub"

        function toggle(): void {
            hub.toggleHub();
        }

        function open(): void {
            hub.openHub();
        }

        function close(): void {
            hub.closeHub();
        }
    }
}
