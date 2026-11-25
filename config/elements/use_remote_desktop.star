# 目的: 自分用サーバの Niri の画面を Moonlight で受け取る。remote-desktop start で、ssh でサーバのセッションを起動してから Moonlight を開く。
# 初回のペアリングは remote-desktop pair で Sunshine の Web UI（ssh のポート転送）を開いて行う。
requires = ["find_home_server"]
needs = ["linux"]

def user_config(find_home_server):
    server = find_home_server.services["serve_remote_desktop"]
    ssh = server["tailnet"]
    helper = shellApp("remote-desktop", [pkg("openssh"), pkg("moonlight-qt")], concat(
        'case "${1:-start}" in\n',
        "  start)\n",
        "    ssh ", ssh, " /run/current-system/sw/bin/remote-niri start\n",
        '    moonlight stream ', server["host"], ' "Extend (Virtual Display)"\n',
        "    ;;\n",
        "  stop)\n",
        "    ssh ", ssh, " /run/current-system/sw/bin/remote-niri stop\n",
        "    ;;\n",
        "  pair)\n",
        "    echo 'Sunshine Web UI: https://localhost:47990 (Ctrl-C to close the tunnel)'\n",
        "    ssh -N -L 47990:localhost:47990 ", ssh, "\n",
        "    ;;\n",
        "  *)\n",
        "    echo 'usage: remote-desktop start|stop|pair' >&2\n",
        "    exit 2\n",
        "    ;;\n",
        "esac\n",
    ))
    return {"home": {"home.packages": [helper, pkg("moonlight-qt")]}}
