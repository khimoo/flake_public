# 手段: 自分用サーバの xsaved を使う。ssh で接続して検索の Web UI を開き、xsaved のコマンドを実行する（クライアントの側。docs/howtouse/xsaved.md）。
requires = ["find_home_server"]

def user_config(find_home_server, machines):
    service = find_home_server.services["serve_xsaved"]
    # ポートは、サーバで xsaved を動かすアカウントの表（[users.xsaved]）にある。
    tables = [account.get("xsaved", {}) for account in machines.all[find_home_server.host]["users"] if account["name"] == service["account"]]
    port = tables[0].get("web_port", 8765)
    # サーバの機体でも同じポートで待ち受けているので、手元の側は別のポートに転送する。
    local_port = port + 10000
    env = {"XSAVED_SERVER": service["tailnet"], "XSAVED_SERVER_PORT": str(port), "XSAVED_LOCAL_PORT": str(local_port)}
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
