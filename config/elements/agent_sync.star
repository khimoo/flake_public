def config(user, host, agent_links):
    root = agent_links.root
    if root == None:
        return {}
    launcher_dir = user.home + "/.local/share/agent-launchers/bin"
    sync = shellAppEnv("agent-sync", [pkg("coreutils"), pkg("gnugrep"), pkg("jq")], {
        "root": root,
        "launcher_dir": launcher_dir,
        "state_dir": user.home + "/.local/state/agent-sync",
        "codex_dir": user.home + "/.codex",
        "settings_file": user.home + "/.claude/settings.json",
        "claude_bin": exe("claude-code", "claude"),
        "codex_bin": exe("codex", "codex"),
        "python_bin": exe("python3", "python3"),
    }, repoText("modules/home-manager/dev/agent-sync.sh"))
    sync_exe = concat(sync, "/bin/agent-sync")
    home = {
        "home.packages": [sync],
        "home.sessionPath": [launcher_dir],
        # JSON が壊れていても switch は止めず、ユーザー設定を保持する。
        "home.activation.agentSync": activation(["linkGeneration"], concat(
            'if [ -n "${DRY_RUN_CMD:-}" ]; then\n  ', sync_exe, ' --dry-run || true\nelse\n  ',
            sync_exe, ' || echo "agent-sync が失敗した。設定 repo の内容を確かめて agent-sync を実行し直す" >&2\nfi\n',
        )),
    }
    if host.linux:
        home["systemd.user.paths.agent-sync"] = {
            "Unit": {"Description": "エージェント設定 repo のプロファイルと設定の変更を反映する"},
            "Path": {
                "PathChanged": [root + "/claude/profiles", root + "/claude/settings.json", root + "/codex"],
                "Unit": "agent-sync.service",
            },
            "Install": {"WantedBy": ["default.target"]},
        }
        home["systemd.user.services.agent-sync"] = {
            "Unit": {"Description": "エージェント設定 repo のプロファイルと設定を反映する"},
            "Service": {"Type": "oneshot", "ExecStart": sync_exe},
        }
    return {"home": home}
