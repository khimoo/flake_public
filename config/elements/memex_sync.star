def writes(memex):
    return [write(memex, {"sync": True})]

def user_config(failure_notify):
    return {"home": {"systemd.user.services.memex-sync.Unit.OnFailure": failure_notify.on_failure}}
