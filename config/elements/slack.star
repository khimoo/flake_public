# 手段: Slack で連絡する。
def writes(gui_apps):
    # ログイン起動と伝え、Slack の起動時非表示設定を使う。手動起動には渡さない。
    return [write(gui_apps, pkg = pkg("slack"), name = "slack", bin = "slack", desktop = "slack.desktop", mime = ["x-scheme-handler/slack"], wayland = True, autostart = True, flags = "--startup")]
