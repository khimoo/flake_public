# 手段: Claude Code の会話の履歴を探す（claude-history）。
# コピーはターミナル（kitty）のクリップボードへ OSC 52 で送る。wl-copy を使うと、Wayland では claude-history を閉じたときに中身が消える。
def user_config():
    history = symlinkJoinBuild("claude-history-osc52", [inputPkg("claude-history", "default")], [pkg("makeWrapper")],
        "wrapProgram $out/bin/claude-history --set CLAUDE_HISTORY_CLIPBOARD osc52\n")
    return {"home": {"home.packages": [history]}}
