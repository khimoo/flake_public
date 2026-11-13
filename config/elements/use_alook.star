# 手段: 自分用サーバの Alook を使う。ssh でポートを転送して Web UI を開く（クライアントの側。docs/howtouse/cli-tools/alook.md）。
# 接続先は利用者の値 home_server。
needs = ["machine_ssh", "tailscale"]

def user_config(user, machine_ssh):
    server = user.home_server
    if server not in machine_ssh.tailnet:
        fail("alook: home_server " + server + " is not a host with ssh_user")
    remotes = "home=" + machine_ssh.lan[server] + " home-ts=" + machine_ssh.tailnet[server]
    return {"home": {"home.packages": [shellAppEnv(
        "alook-open",
        [pkg("openssh"), pkg("iproute2"), pkg("coreutils"), pkg("util-linux"), pkg("xdg-utils")],
        {"ALOOK_OPEN_REMOTES": remotes},
        repoText("modules/home-manager/dev/alook-open.sh"),
    )]}}
