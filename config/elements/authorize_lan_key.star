# 手段: 自宅の機体どうしの ssh の公開鍵（持ち主の値 lan_public_key）を、このアカウントの authorized_keys に入れる。
def user_config(user, owner):
    return {"nixos": {("users", "users", user.name, "openssh", "authorizedKeys", "keys"): [owner.lan_public_key]}}
