# 目的: 自分用サーバとして、Alook（エージェントを動かす Web UI）を公開する（サーバの側。docs/howtouse/cli-tools/alook.md）。
# alook-app の版を固定しているのは x86_64-linux の配布物だけ。
needs = ["x86_64_linux"]
requires = ["machine_ssh"]

def user_config():
    return {"home": {"home.packages": [repoPkg("packages/alook")]}}
