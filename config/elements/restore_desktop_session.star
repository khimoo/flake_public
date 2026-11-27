# 目的: ローカルの Niri にログインすると、前回のウィンドウ配置から作業を再開する。
requires = ["niri"]
needs = ["nixos_system"]

def writes(gui_apps):
    return [write(
        gui_apps,
        pkg = repoPkg("packages/nirinit"),
        # 独自のトレイ・最小化オプションを使う自動起動は既存のランチャーに任せる。
        session_restore = ["discord", "Slack", "slack", "twindesk", "Bitwarden", "bitwarden", "lunarclient"],
    )]
