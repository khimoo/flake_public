# 手段: 自宅の機体どうしの ssh に使う鍵（全機体で共通）を、connect_ssh の Host ブロックが読む場所に置く。
# 公開鍵は authorize_lan_key が、ログインを受け付けるアカウントの authorized_keys に入れる。
def public(user, connect_ssh):
    return {"path": user.home + "/" + connect_ssh.identity_file}

def writes(lan_ssh_key, secrets):
    return [write(secrets, {"secret": "lan_ssh_key", "path": lan_ssh_key.path, "mode": "600"})]
