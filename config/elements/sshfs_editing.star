# 目的: sshfs で別の PC のファイルを編集する。
requires = ["lan_ssh_key"]
def user_config():
    return {"home": {"home.packages": [pkg("sshfs")]}}
