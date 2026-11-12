# 目的: sshfs で別の PC のファイルを編集する。
def user_config():
    return {"home": {"home.packages": [pkg("sshfs")]}}
