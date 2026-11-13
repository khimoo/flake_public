# 手段: 自分用サーバの xsaved を使う。ssh で接続して検索の Web UI を開き、xsaved のコマンドを実行する（クライアントの側。docs/howtouse/xsaved.md）。
# 接続先は利用者の値 home_server。
needs = ["machine_ssh", "tailscale"]
requires = ["lan_ssh_key"]

def user_config(user, machine_ssh, machines):
    server = user.home_server
    if server not in machine_ssh.tailnet:
        fail("xsaved: home_server " + server + " is not a host with ssh_user")
    values = machines.all[server].get("xsaved_users", {}).get(user.name)
    if values == None:
        fail("xsaved: home_server " + server + " has no [xsaved_users." + user.name + "]")
    port = values.get("web_port", 8765)
    # サーバの機体でも同じポートで待ち受けているので、手元の側は別のポートに転送する。
    local_port = port + 10000
    env = {"XSAVED_SERVER": machine_ssh.tailnet[server], "XSAVED_SERVER_PORT": str(port), "XSAVED_LOCAL_PORT": str(local_port)}
    remote = shellAppEnv("xsaved-remote", [pkg("openssh")], env, repoText("modules/home-manager/xsaved/remote.sh"))
    web = shellAppEnv("xsaved-web", [pkg("openssh"), pkg("xdg-utils")], env, repoText("modules/home-manager/xsaved/web.sh"))
    return {"home": {
        "home.packages": [remote, web],
        ("xdg", "desktopEntries", "xsaved-web"): {
            "name": "X の保存（xsaved）",
            "comment": "自分用サーバの xsaved の検索画面を開く",
            "exec": concat(web, "/bin/xsaved-web"),
            "categories": ["Network"],
        },
    }}
