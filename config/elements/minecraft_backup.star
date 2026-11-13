def user_config(user, host, failure_notify):
    repo_parent = host.minecraft_repo.rsplit("/", 1)[0]
    env = {
        "MC_INSTANCES": user.home + "/.local/share/PrismLauncher/instances",
        "MC_REPO": host.minecraft_repo,
        "MC_REMOTE": host.minecraft_remote,
        "MC_RETENTION": " ".join(getattr(host, "minecraft_retention", ["--keep-last=3", "--keep-daily=14", "--keep-weekly=8", "--keep-monthly=12"])),
        "MC_WARN_GIB": str(getattr(host, "minecraft_warn_gib", 10)),
    }
    commands = {}
    for name in ["backup", "check", "restore", "sync"]:
        commands[name] = shellAppEnv("mc-" + name, [pkg(p) for p in ["restic", "rclone", "jq", "procps", "coreutils", "gnugrep"]], env,
            concat(repoText("modules/home-manager/minecraft-common.sh"), repoText("modules/home-manager/minecraft-" + name + ".sh")))
    setup = shellAppEnv("mc-setup-hooks", [pkg(p) for p in ["procps", "coreutils", "gnugrep", "gawk"]],
        {"MC_PRISM_CFG": user.home + "/.local/share/PrismLauncher/prismlauncher.cfg"}, repoText("modules/home-manager/minecraft-setup-hooks.sh"))
    return {"nixos": {"systemd.tmpfiles.rules": ["d " + repo_parent + " 0755 " + user.name + " users -"]}, "home": {
        "home.packages": commands.values() + [setup],
        "systemd.user.services.mc-sync": {
            "Unit": {"Description": "Minecraft バックアップの刈り込みと Drive への同期", "OnFailure": failure_notify.on_failure},
            "Service": {"Type": "oneshot", "ExecStart": concat(commands["sync"], "/bin/mc-sync")},
        },
        "systemd.user.timers.mc-sync": {
            "Unit": {"Description": "Minecraft バックアップの刈り込みと Drive への同期"},
            "Timer": {"OnCalendar": "daily", "Persistent": True, "RandomizedDelaySec": "10m"},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }}
