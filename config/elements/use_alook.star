# 手段: 自分用サーバの Alook を使う。ssh でポートを転送して Web UI を開く（クライアントの側。docs/howtouse/cli-tools/alook.md）。
requires = ["find_home_server"]

def user_config(find_home_server):
    service = find_home_server.services["serve_alook"]
    remotes = "home=" + service["lan"] + " home-ts=" + service["tailnet"]
    return {"home": {"home.packages": [shellAppEnv(
        "alook-open",
        [pkg("openssh"), pkg("iproute2"), pkg("coreutils"), pkg("util-linux"), pkg("xdg-utils")],
        {"ALOOK_OPEN_REMOTES": remotes},
        repoText("modules/home-manager/dev/alook-open.sh"),
    )]}}
