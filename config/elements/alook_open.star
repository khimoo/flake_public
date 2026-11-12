# `alook-open`: 手元または別の PC の Alook の Web UI をブラウザで開く（docs/howtouse/cli-tools/alook.md）。
# 開ける別の PC は、ホストのファイルの alook_open_remotes（名前: SSH の接続名）。
def user_config(host):
    if "local" in host.alook_open_remotes:
        fail("alook_open_remotes: 名前 local は手元の PC に使う")
    remotes = " ".join([name + "=" + remote for name, remote in sorted(host.alook_open_remotes.items())])
    return {"home": {"home.packages": [shellAppEnv(
        "alook-open",
        [pkg("openssh"), pkg("iproute2"), pkg("coreutils"), pkg("util-linux"), pkg("xdg-utils")],
        {"ALOOK_OPEN_REMOTES": remotes},
        repoText("modules/home-manager/dev/alook-open.sh"),
    )]}}
