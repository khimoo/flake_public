# 手段: Codex を使う。サブエージェントを止める方針は codex_policy が /etc に書く。
requires = ["codex_policy", "graphify"]

def user_config():
    return {"home": {"home.packages": [pkg("codex")]}}
