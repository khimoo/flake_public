def config(user, host, failure_notify):
    archive = host.quaderno_archive
    if not archive.startswith("/"):
        fail("quaderno: archive must be an absolute path")
    if archive.startswith("/home/") and not archive.startswith(user.home + "/"):
        fail("quaderno: archive points to another user's home")
    dptrp1 = repoPkg("packages/dpt-rp1-py")
    scripts = command("quaderno-scripts", concat(
        'mkdir -p "$out"\ncp ', repoPath("modules/home-manager/quaderno_plan.py"), ' "$out/quaderno_plan.py"\ncp ',
        repoPath("modules/home-manager/quaderno_pull.py"), ' "$out/quaderno_pull.py"\n',
    ))
    pull = shellAppEnv("quaderno-pull", [pythonWithModules([dptrp1])], {
        "QUADERNO_SERIAL": getattr(host, "quaderno_serial", None) or "",
        "QUADERNO_ARCHIVE_DIR": archive,
        "QUADERNO_REMOTE_ROOT": getattr(host, "quaderno_remote_root", "Document"),
        "QUADERNO_DISCOVERY_TIMEOUT": str(getattr(host, "quaderno_discovery_timeout", 15)),
        "QUADERNO_STATE_FILE": user.home + "/.local/state/quaderno/state.json",
    }, concat('exec python3 ', scripts, '/quaderno_pull.py "$@"\n'))
    return {"home": {
        "home.packages": [pull, dptrp1],
        "systemd.user.services.quaderno-pull": {
            "Unit": {"Description": "Quaderno から未取得の文書を取り込む", "ConditionPathIsDirectory": archive, "OnFailure": failure_notify.on_failure},
            "Service": {"Type": "oneshot", "ExecStart": concat(pull, "/bin/quaderno-pull")},
        },
        "systemd.user.timers.quaderno-pull": {
            "Unit": {"Description": "Quaderno の取り込みを定期的に試す"},
            "Timer": {"OnActiveSec": "2min", "OnUnitActiveSec": str(getattr(host, "quaderno_interval", 3600)) + "s"},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }}
