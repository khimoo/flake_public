# 目的: Send フォルダに置いた PDF を Quaderno へ送る（docs/howtouse/quaderno.md）。
def writes(quaderno, user, host):
    return [write(quaderno, {"send": {
        "dir": getattr(host, "quaderno_send_dir", user.home + "/Quaderno/Send"),
        "remote": getattr(host, "quaderno_send_remote", "Document/Received"),
    }})]
