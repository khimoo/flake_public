# 手段: xsaved の取得したツイートとデータベースを、restic で [xsaved_users.<利用者>] の backup_repository に毎日写し、復元を確かめるコマンドを入れる。
def user_config(user, serve_xsaved, failure_notify):
    values = serve_xsaved.users[user.name]
    password = values["backup_password_file"]
    if not password.startswith("/"):
        fail("xsaved: backup_password_file must be an absolute path")
    env = {
        "XSAVED_DATA_DIR": values["data_dir"],
        "XSAVED_PROJECT_DIR": values["project_dir"],
        "XSAVED_DATABASE": values.get("database", "xsaved"),
        "XSAVED_CHECK_MOUNT": "true" if values.get("check_mount", False) else "false",
        "RESTIC_REPOSITORY": values["backup_repository"],
        "RESTIC_PASSWORD_FILE": password,
        "FLAKE_REV": flakeRev(),
    }
    backup = shellAppEnv("xsaved-backup", [pkg(p) for p in ["restic", "rclone", "util-linux", "git"]] + [serve_xsaved.postgresql], env, repoText("modules/home-manager/xsaved/backup.sh"))
    restore = shellAppEnv("xsaved-restore-check", [pkg(p) for p in ["restic", "rclone", "coreutils", "gnused"]] + [serve_xsaved.postgresql_extensions], env, repoText("modules/home-manager/xsaved/restore-check.sh"))
    return {"home": {
        "home.packages": [restore],
        "systemd.user.services.xsaved-backup": {
            "Unit": {"Description": "取得したツイートとデータベースを restic で写す", "OnFailure": failure_notify.on_failure, "X-SwitchMethod": "keep-old"},
            "Service": {"Type": "oneshot", "ExecStart": concat(backup, "/bin/xsaved-backup"), "Nice": 10, "IOSchedulingClass": "idle"},
        },
        "systemd.user.timers.xsaved-backup": {
            "Unit": {"Description": "取得したツイートとデータベースを毎日写す"},
            "Timer": {"OnCalendar": "*-*-* 06:00:00", "Persistent": True},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }}
