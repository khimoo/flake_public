# 手段: Slack で連絡する。
def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("slack"), "name": "slack", "bin": "slack", "desktop": "slack.desktop", "mime": ["x-scheme-handler/slack"], "wayland": True, "autostart": True, "flags": "--silent"})]
