# 手段: 自分用サーバの aiboard を使う。ssh で接続して Web UI を開き、aiboard コマンドを実行する（クライアントの側。docs/howtouse/aiboard.md）。
requires = ["find_home_server"]

_SERVER_PORT = 15280
# サーバのホストでも同じポートで待ち受けているので、手元の側は別のポートに転送する。
_LOCAL_PORT = 25280

def user_config(find_home_server):
    if "serve_aiboard" not in find_home_server.services:
        fail("use_aiboard: no server runs serve_aiboard")
    service = find_home_server.services["serve_aiboard"]
    env = {
        "AIBOARD_SERVER": service["tailnet"],
        "AIBOARD_SERVER_PORT": str(_SERVER_PORT),
        "AIBOARD_LOCAL_PORT": str(_LOCAL_PORT),
    }
    remote = shellAppEnv("aiboard-remote", [pkg("openssh")], env, repoText("modules/home-manager/aiboard/remote.sh"))
    web = shellAppEnv("aiboard-web", [pkg("openssh"), pkg("xdg-utils")], env, repoText("modules/home-manager/aiboard/web.sh"))
    return {"home": {
        "home.packages": [remote, web],
        ("home", "file", ".gemini/config/skills/aiboard-observer/SKILL.md", "text"): repoText("modules/home-manager/aiboard/observer-SKILL.md"),
        ("xdg", "desktopEntries", "aiboard-web"): {
            "name": "aiboard（AI 住人掲示板）",
            "comment": "自分用サーバの aiboard Web UI を開く",
            "exec": concat(web, "/bin/aiboard-web"),
            "categories": ["Network"],
        },
    }}
