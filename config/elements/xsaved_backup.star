# 手段: xsaved の取得したツイートとデータベースを、restic で利用者の表の backup_repository に毎日写し、復元を確かめるコマンドを入れる。
# restic のパスワード（秘密 xsaved_restic_password）も、この要素が置く。
def _password_file(user):
    return user.home + "/.config/xsaved/restic-password"

def writes(user, secrets):
    return [write(secrets, {"secret": "xsaved_restic_password", "path": _password_file(user), "mode": "600"})]

def user_config(user, serve_xsaved, failure_notify):
    env = {
        "XSAVED_DATA_DIR": serve_xsaved.data_dir,
        "XSAVED_PROJECT_DIR": serve_xsaved.project_dir,
        "XSAVED_DATABASE": serve_xsaved.database,
        "XSAVED_CHECK_MOUNT": "true" if serve_xsaved.check_mount else "false",
        "RESTIC_REPOSITORY": serve_xsaved.values["backup_repository"],
        "RESTIC_PASSWORD_FILE": _password_file(user),
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
