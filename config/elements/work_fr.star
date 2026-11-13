# 行動: fr の仕事の連絡（Slack）。
def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("slack"), "name": "slack", "bin": "slack", "desktop": "slack.desktop", "mime": ["x-scheme-handler/slack"], "wayland": True, "autostart": True, "flags": "--silent"})]
