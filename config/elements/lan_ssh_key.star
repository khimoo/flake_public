# 手段: 自宅の機体どうしの ssh に使う鍵（全機体で共通の id_lan）を置く。公開鍵は authorize_lan_key が、ログインを受け付けるアカウントの authorized_keys に入れる。
def writes(user, secrets):
    return [write(secrets, {"secret": "lan_ssh_key", "path": user.home + "/.ssh/id_lan", "mode": "600"})]
