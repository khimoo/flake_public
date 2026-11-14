# 目的: Quaderno の受け渡しフォルダと PDF をやりとりする（docs/howtouse/quaderno.md）。
# Send フォルダに置いた PDF を送り、quaderno-receive を実行したときに受け渡しフォルダの PDF を手元へ落とす。
_KEEP = "7d"

def writes(quaderno, user, host):
    return [write(quaderno, {"exchange": {
        "remote": getattr(host, "quaderno_exchange_remote", "Document/PC-Exchange"),
        "send_dir": getattr(host, "quaderno_send_dir", user.home + "/Quaderno/Send"),
        "receive_dir": _cache(user) + "/Received",
        "receive_state": _cache(user) + "/received.json",
    }})]

def _cache(user):
    return user.home + "/.cache/quaderno"

def user_config(user):
    received = _cache(user) + "/Received"
    return {"home": {"systemd.user.tmpfiles.rules": [
        "d " + received + " 0700 - - " + _KEEP,
        "L " + user.home + "/Quaderno/Received - - - - " + received,
    ]}}
