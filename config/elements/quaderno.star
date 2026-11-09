def config(user, host, failure_notify):
    archive = host.quaderno_archive
    if not archive.startswith("/"):
        fail("quaderno: archive must be an absolute path")
    if archive.startswith("/home/") and not archive.startswith(user.home + "/"):
        fail("quaderno: archive points to another user's home")
    dptrp1 = repoPkg("packages/dpt-rp1-py")
    scripts = command("quaderno-scripts", concat(
        'mkdir -p "$out"\ncp ', repoPath("modules/home-manager/quaderno_plan.py"), ' "$out/quaderno_plan.py"\ncp ',
        repoPath("modules/home-manager/quaderno_transfer.py"), ' "$out/quaderno_transfer.py"\n',
    ))
    transfer = shellAppEnv("quaderno-transfer", [pythonWithModules([dptrp1])], {
        "QUADERNO_SERIAL": getattr(host, "quaderno_serial", None) or "",
        "QUADERNO_ARCHIVE_DIR": archive,
        "QUADERNO_REMOTE_ROOT": getattr(host, "quaderno_remote_root", "Document"),
        "QUADERNO_DISCOVERY_TIMEOUT": str(getattr(host, "quaderno_discovery_timeout", 15)),
        "QUADERNO_STATE_FILE": user.home + "/.local/state/quaderno/state.json",
        "QUADERNO_SEND_DIR": getattr(host, "quaderno_send_dir", user.home + "/Quaderno/Send"),
        "QUADERNO_SEND_REMOTE": getattr(host, "quaderno_send_remote", "Document/Received"),
    }, concat('exec python3 ', scripts, '/quaderno_transfer.py "$@"\n'))
    return {"home": {
        "home.packages": [transfer, dptrp1],
        "systemd.user.services.quaderno-transfer": {
            "Unit": {"Description": "Quaderno から文書を取り込み、Send フォルダの PDF を送る", "ConditionPathIsDirectory": archive, "OnFailure": failure_notify.on_failure},
            "Service": {"Type": "oneshot", "ExecStart": concat(transfer, "/bin/quaderno-transfer")},
        },
        # Quaderno は起きている短い間しか Wi-Fi に居ない。間隔を長くすると、その間を逃して何も受け渡せない。
        "systemd.user.timers.quaderno-transfer": {
            "Unit": {"Description": "Quaderno が居るかを定期的に確かめる"},
            "Timer": {"OnActiveSec": "2min", "OnUnitActiveSec": str(getattr(host, "quaderno_interval", 60)) + "s"},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }}
