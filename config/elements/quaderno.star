# Quaderno を LAN で探し、見つかったら受け渡すコマンドと、systemd のユーザー timer。
# LAN に見つからないときは、ペアリング済みの Quaderno に Bluetooth の PAN をつないで探す。
# 何を受け渡すかは、書き込んだ要素で決まる（use_quaderno_archive は取り込み、quaderno_exchange は受け渡しフォルダ）。
def user_config(host, failure_notify, incoming):
    pull = None
    exchange = None
    for w in incoming:
        pull = w.value.get("pull", pull)
        exchange = w.value.get("exchange", exchange)
    env = {
        "QUADERNO_SERIAL": getattr(host, "quaderno_serial", None) or "",
        "QUADERNO_DISCOVERY_TIMEOUT": str(getattr(host, "quaderno_discovery_timeout", 15)),
    }
    if pull:
        env["QUADERNO_ARCHIVE_SSH"] = pull["ssh"]
        env["QUADERNO_REMOTE_ROOT"] = pull["remote_root"]
    if exchange:
        env["QUADERNO_EXCHANGE_REMOTE"] = exchange["remote"]
        env["QUADERNO_SEND_DIR"] = exchange["send_dir"]
        env["QUADERNO_RECEIVE_DIR"] = exchange["receive_dir"]
        env["QUADERNO_RECEIVE_STATE"] = exchange["receive_state"]
    dptrp1 = repoPkg("packages/dpt-rp1-py")
    scripts = command("quaderno-scripts", concat(
        'mkdir -p "$out"\ncp ', repoPath("modules/home-manager/quaderno_plan.py"), ' "$out/quaderno_plan.py"\ncp ',
        repoPath("modules/home-manager/quaderno_archive.py"), ' "$out/quaderno_archive.py"\ncp ',
        repoPath("modules/home-manager/quaderno_transfer.py"), ' "$out/quaderno_transfer.py"\n',
    ))
    inputs = [pythonWithModules([dptrp1]), pkg("openssh"), pkg("bluez"), pkg("networkmanager")]
    transfer = shellAppEnv("quaderno-transfer", inputs, env,
        concat('exec python3 ', scripts, '/quaderno_transfer.py "$@"\n'))
    packages = [transfer, dptrp1]
    home = {
        "systemd.user.services.quaderno-transfer": {
            "Unit": {"Description": "Quaderno の文書を取り込み、Send の PDF を送る", "OnFailure": failure_notify.on_failure},
            "Service": {"Type": "oneshot", "ExecStart": concat(transfer, "/bin/quaderno-transfer --no-wait")},
        },
        # 取り込みは、コマンドを使わない日のための保険。Quaderno が起きている間と重ならない回は何もしない。
        "systemd.user.timers.quaderno-transfer": {
            "Unit": {"Description": "Quaderno の文書を定期的に取り込む"},
            "Timer": {"OnActiveSec": "2min", "OnUnitActiveSec": str(getattr(host, "quaderno_archive_interval", 3600)) + "s"},
            "Install": {"WantedBy": ["timers.target"]},
        },
    }
    if exchange:
        packages += [
            shellAppEnv("quaderno-send", inputs, env, concat('exec python3 ', scripts, '/quaderno_transfer.py send "$@"\n')),
            shellAppEnv("quaderno-receive", inputs, env, concat('exec python3 ', scripts, '/quaderno_transfer.py receive "$@"\n')),
        ]
        home["systemd.user.services.quaderno-send"] = {
            "Unit": {
                "Description": "Send フォルダの PDF を Quaderno へ送る",
                "OnFailure": failure_notify.on_failure,
                # Send が空の間は Quaderno を探さない。探索と Bluetooth の接続を毎分繰り返さずに済む。
                "ConditionDirectoryNotEmpty": exchange["send_dir"],
            },
            "Service": {"Type": "oneshot", "ExecStart": concat(transfer, "/bin/quaderno-transfer --no-wait")},
        }
        # Quaderno は起きている短い間しか通信できない。間隔を長くすると、その間を逃して送れない。
        home["systemd.user.timers.quaderno-send"] = {
            "Unit": {"Description": "Send フォルダに PDF があれば Quaderno へ送る"},
            "Timer": {"OnActiveSec": "1min", "OnUnitActiveSec": str(getattr(host, "quaderno_interval", 60)) + "s"},
            "Install": {"WantedBy": ["timers.target"]},
        }
    home["home.packages"] = packages
    return {"home": home}
