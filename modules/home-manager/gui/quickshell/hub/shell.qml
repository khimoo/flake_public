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

    // ショートカットからは Qt の CLI を毎回起動せず、常駐ハブへ直接送る。
    SocketServer {
        readonly property string runtimeDir: Quickshell.env("RUNTIME_DIRECTORY") || ""
        path: runtimeDir === "" ? "" : runtimeDir + "/toggle.sock"
        active: path !== ""

        handler: Socket {
            id: peer
            property bool handled: false

            parser: SplitParser {
                onRead: message => {
                    if (peer.handled) return;
                    peer.handled = true;
                    if (message === "toggle") {
                        hub.toggleHub();
                        peer.write("ok\n");
                    } else {
                        peer.write("invalid\n");
                    }
                    peer.flush();
                    peer.connected = false;
                }
            }
        }
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
