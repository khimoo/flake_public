def config(host):
    history = inputPkg("claude-history", "default")
    if host.linux:
        # claude-history の yank は wl-copy / xclip が PATH に無いと arboard に戻り、
        # Wayland では TUI 終了時にクリップボードの内容が消える。
        history = symlinkJoinBuild("claude-history-with-clipboard", [history], [pkg("makeWrapper")], concat(
            "wrapProgram $out/bin/claude-history \\\n  --prefix PATH : ",
            pkg("wl-clipboard"), "/bin:", pkg("xclip"), "/bin\n",
        ))
    return {"home": {"home.packages": [
        pkg("claude-code"),
        history,
        pkg("codex"),
        pkg("graphify"),
        repoPkg("packages/happy"),
        pkg("google-clasp"),
        pkg("rclone"),
    ]}}
