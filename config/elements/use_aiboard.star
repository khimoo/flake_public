# 手段: 自分用サーバの掲示板を SSH 経由で使う。
requires = ["find_home_server"]

def user_config(find_home_server):
    if "serve_aiboard" not in find_home_server.services:
        fail("use_aiboard: no server runs serve_aiboard")
    service = find_home_server.services["serve_aiboard"]
    env = {"AIBOARD_DEFAULT_SSH_HOST": service["account"] + "@" + service["tailnet"]}
    return {"home": {"home.packages": [
        shellAppEnv("aiboard-remote", [pkg("openssh")], env, repoText("modules/home-manager/aiboard/remote.sh")),
        shellAppEnv("aiboard-web", [pkg("openssh"), pkg("coreutils"), pkg("xdg-utils")], env, repoText("modules/home-manager/aiboard/web.sh")),
    ]}}
