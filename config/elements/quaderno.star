# Quaderno を LAN で探し、見つかったら受け渡す systemd のユーザー timer。
# 何を受け渡すかは、書き込んだ要素で決まる（quaderno_backup は取り込み、quaderno_send は送信）。
def user_config(host, failure_notify, incoming):
    pull = None
    send = None
    for w in incoming:
        pull = w.value.get("pull", pull)
        send = w.value.get("send", send)
    env = {
        "QUADERNO_SERIAL": getattr(host, "quaderno_serial", None) or "",
        "QUADERNO_DISCOVERY_TIMEOUT": str(getattr(host, "quaderno_discovery_timeout", 15)),
    }
    unit = {"Description": "Quaderno と PDF を受け渡す", "OnFailure": failure_notify.on_failure}
    if pull:
        env["QUADERNO_ARCHIVE_SSH"] = pull["ssh"]
        env["QUADERNO_REMOTE_ROOT"] = pull["remote_root"]
    if send:
        env["QUADERNO_SEND_DIR"] = send["dir"]
        env["QUADERNO_SEND_REMOTE"] = send["remote"]
    dptrp1 = repoPkg("packages/dpt-rp1-py")
    scripts = command("quaderno-scripts", concat(
        'mkdir -p "$out"\ncp ', repoPath("modules/home-manager/quaderno_plan.py"), ' "$out/quaderno_plan.py"\ncp ',
        repoPath("modules/home-manager/quaderno_archive.py"), ' "$out/quaderno_archive.py"\ncp ',
        repoPath("modules/home-manager/quaderno_transfer.py"), ' "$out/quaderno_transfer.py"\n',
    ))
    transfer = shellAppEnv("quaderno-transfer", [pythonWithModules([dptrp1]), pkg("openssh")], env,
        concat('exec python3 ', scripts, '/quaderno_transfer.py "$@"\n'))
    return {"home": {
        "home.packages": [transfer, dptrp1],
        "systemd.user.services.quaderno-transfer": {
            "Unit": unit,
            "Service": {"Type": "oneshot", "ExecStart": concat(transfer, "/bin/quaderno-transfer")},
        },
        # Quaderno は起きている短い間しか Wi-Fi に居ない。間隔を長くすると、その間を逃して何も受け渡せない。
        "systemd.user.timers.quaderno-transfer": {
            "Unit": {"Description": "Quaderno が居るかを定期的に確かめる"},
            "Timer": {"OnActiveSec": "2min", "OnUnitActiveSec": str(getattr(host, "quaderno_interval", 60)) + "s"},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }}
