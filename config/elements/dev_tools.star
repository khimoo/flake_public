# 目的: プログラムを書くときに使う CLI の道具。
requires = ["rust"]
def user_config():
    return {"home": {"home.packages": [
        pkg("tree"),
    ]}}
