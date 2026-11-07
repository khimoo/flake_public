# 目的: memex の vault のバイナリを git-annex で Drive と同期する。
def writes(memex):
    return [write(memex, {"sync": True})]

def config():
    # 同期の失敗をデスクトップに通知する。値は failure-notify.nix の local.failureNotify.onFailure。
    return {"home": {"systemd.user.services.memex-sync.Unit.OnFailure": ["notify-failure@%n.service"]}}
